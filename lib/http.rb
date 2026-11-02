# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# Http is the one HTTP client the port's network code shares.
#
# Ported from podcasts-data/src/http.rs. Upstream builds a `reqwest::Client`
# with a redirect policy that stops on a loop and gives up past twenty hops, no
# referer, and a twenty second connect timeout, and wraps it in a
# `RetryContext` that tries the app's own user agent first and falls back to the
# generic browser one, because some servers reject each of them.
#
# The two user agents are upstream's, except that the custom one names this
# port rather than upstream — a server that blocks one app's agent should not
# have the other blamed for it.
module Http
  USER_AGENT_CUSTOM = "gnome-podcasts-rb"
  # Upstream's USER_AGENT_GENERIC, which originates from the Tor browser. Some
  # servers reject the custom agent and accept this one.
  USER_AGENT_GENERIC = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"

  MAX_REDIRECTS = 20
  MAX_RETRIES = 2
  CONNECT_TIMEOUT = 20
  READ_TIMEOUT = 120

  Error = Class.new(StandardError)

  class << self
    # Upstream's RetryContext::prepared_send: the custom agent first, then the
    # generic one, up to MAX_RETRIES attempts. The block, when given, receives
    # the streaming response; without one the whole body is answered.
    def get(url, headers: {}, &block)
      attempt(
        agents,
        url,
        headers,
        &block
      )
    end

    # A GET whose body is parsed as JSON, which is how both discovery
    # platforms and the Nextcloud endpoints answer.
    def get_json(url, headers: {})
      JSON.parse(get(url, headers: headers.merge("Accept" => "application/json")))
    end

    # Upstream's Url::parse_with_params.
    def url_with_params(base, params)
      URI.parse(base).then do |parsed|
        URI.decode_www_form(parsed.query.to_s).then do |existing|
          parsed.query = URI.encode_www_form(existing + params.to_a)
          parsed.to_s
        end
      end
    end

    private

      def agents = [USER_AGENT_CUSTOM, USER_AGENT_GENERIC].first(MAX_RETRIES + 1)

      # One agent per try, the next one taking over when the one before it
      # failed, and the last failure raised.
      def attempt(remaining, url, headers, &block)
        request(
          url,
          remaining.first,
          headers,
          &block
        )
      rescue StandardError => e
        if remaining.length > 1
          attempt(
            remaining.drop(1),
            url,
            headers,
            &block
          )
        else
          raise Error, "GET #{url} failed: #{e.message}"
        end
      end

      # One attempt, following redirects the way upstream's policy does: stop
      # on a redirect back to where we just were, give up past MAX_REDIRECTS.
      def request(url, agent, headers, seen = [], &block)
        URI.parse(url).then do |parsed|
          Net::HTTP.start(
            parsed.host,
            parsed.port,
            use_ssl:      parsed.scheme == "https",
            open_timeout: CONNECT_TIMEOUT,
            read_timeout: READ_TIMEOUT,
          ) do |http|
            http.request(get_request(parsed, agent, headers)) do |response|
              handle(
                response,
                parsed,
                agent,
                headers,
                seen,
                &block
              )
            end
          end
        end
      end

      def handle(response, parsed, agent, headers, seen, &block)
        if response.is_a?(Net::HTTPRedirection)
          redirect(
            response,
            parsed,
            agent,
            headers,
            seen,
            &block
          )
        elsif response.is_a?(Net::HTTPSuccess)
          if block
            block.call(response)
          else
            response.read_body
          end
        else
          raise Error, "unexpected response #{response.code} for #{parsed}"
        end
      end

      def redirect(response, parsed, agent, headers, seen, &block)
        URI.join(parsed, response["location"].to_s).to_s.then do |target|
          if seen.length >= MAX_REDIRECTS
            raise Error, "too many redirects for #{parsed}"
          elsif seen.last == target
            raise Error, "redirect loop at #{target}"
          else
            request(
              target,
              agent,
              headers,
              seen + [parsed.to_s],
              &block
            )
          end
        end
      end

      # Upstream turns the referer off, so nothing is sent beyond the agent
      # and whatever the caller asked for.
      def get_request(parsed, agent, headers)
        Net::HTTP::Get.new(parsed.request_uri).tap do |http_get|
          http_get["User-Agent"] = agent
          headers.each { |key, value| http_get[key] = value }
        end
      end
  end
end
