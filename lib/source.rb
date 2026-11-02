# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "database"
require_relative "errors"

# Source is a feed url, plus the HTTP validators that keep refetching it
# cheap.
#
# Ported from podcasts-data/src/models/source.rs and
# podcasts-data/src/models/new_source.rs: `from_url` indexes the url, and
# `into_feed` does the conditional GET, follows redirects, remembers the ETag
# and Last-Modified headers and hands back a `Feed` to index.
class Source
  USER_AGENT = "gnome-podcasts-rb"
  MAX_REDIRECTS = 5

  class << self
    # Upstream's Source::from_url: index the url (not the feed) and answer the
    # stored row.
    def from_url(uri)
      clean_url(uri).then do |url|
        Database.connection.insert("source", "uri" => url).then { |row| from_row(row) }
      end
    end

    def from_row(row) = new(row)

    # Upstream's utils::url_cleaner — drop the fragment, keep the query.
    def clean_url(uri)
      URI.parse(uri.to_s.strip).then do |parsed|
        parsed.fragment = nil
        parsed.to_s
      end
    rescue URI::InvalidURIError
      uri.to_s.strip
    end
  end

  def initialize(row)
    @row = row.transform_keys(&:to_s)
  end

  def id = @row["id"]
  def uri = @row["uri"].to_s
  def last_modified = @row["last_modified"]
  def http_etag = @row["http_etag"]
  def to_h = @row.dup

  def uri=(value)
    @row["uri"] = value
    value
  end

  def last_modified=(value)
    @row["last_modified"] = value
    value
  end

  def http_etag=(value)
    @row["http_etag"] = value
    value
  end

  def save
    Database.connection.update("source", id, @row)
    self
  end

  # Fetches the feed and answers the `Feed` to index.
  #
  # Raises Errors::FeedNotModified when the server answers 304, which is how
  # upstream skips an unchanged feed, and Errors::HttpStatusError for the
  # statuses upstream calls out by name.
  #
  # `feed` is not required here: it requires this file in turn, and the
  # callers that fetch a feed (lib/pipeline.rb and the specs) load it.
  def into_feed
    Feed.new(channel: XmlParser.parse(fetch_body), source_id: id)
  end

  # The response body, after redirects and validator bookkeeping.
  def fetch_body
    MAX_REDIRECTS.times.inject(nil) do |body, _attempt|
      body || match_status(request(uri))
    end.then do |body|
      unless body.is_a?(String)
        raise Errors::HttpStatusError.new(uri, "redirects", "Too many redirects")
      end

      body
    end
  end

  private

    def request(url)
      URI.parse(url).then do |parsed|
        Net::HTTP.start(
          parsed.host,
          parsed.port,
          use_ssl:      parsed.scheme == "https",
          open_timeout: 20,
          read_timeout: 60,
        ) { |http| http.request(get_request(parsed)) }
      end
    end

    def get_request(parsed)
      Net::HTTP::Get.new(parsed.request_uri).tap do |get|
        get["User-Agent"] = USER_AGENT
        if http_etag
          get["If-None-Match"] = http_etag
        end
        if last_modified
          get["If-Modified-Since"] = last_modified
        end
        if parsed.userinfo
          get.basic_auth(parsed.user.to_s, parsed.password.to_s)
        end
      end
    end

    # Upstream's Source::match_status: store the validators on success and on
    # 304, clear them otherwise, follow the redirects and name the failures.
    def match_status(response)
      code = response.code.to_i
      if code == 304
        update_etag(response)
        raise Errors::FeedNotModified, self
      end

      if (200..299).cover?(code)
        update_etag(response)
        response.body
      else
        clear_etags
        save
        follow_or_fail(response, code)
      end
    end

    def follow_or_fail(response, code)
      if [301, 302, 307, 308].include?(code)
        redirect(response, code)
        nil
      else
        raise Errors::HttpStatusError.new(uri, code, status_context(code))
      end
    end

    def status_context(code)
      {
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not found",
        408 => "Request Timeout",
        410 => "Feed was deleted",
      }.fetch(code, "HTTP error")
    end

    # A permanent redirect rewrites the stored url, as upstream's update_url
    # does; a temporary one is followed without touching the row.
    def redirect(response, code)
      response["location"].then do |location|
        unless location
          raise Errors::HttpStatusError.new(uri, code, "Redirect without a location")
        end

        URI.join(uri, location).to_s.then do |new_url|
          if [301, 308].include?(code)
            self.uri = new_url
            clear_etags
            save
          end
          @row["uri"] = new_url
        end
      end
    end

    def update_etag(response)
      [response["etag"], response["last-modified"]].then do |etag, modified|
        if etag != http_etag || modified != last_modified
          self.http_etag = etag
          self.last_modified = modified
          save
        end
      end
    end

    def clear_etags
      @row["http_etag"] = nil
      @row["last_modified"] = nil
    end
end
