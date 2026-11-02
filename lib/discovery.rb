# frozen_string_literal: true

require "time"
require_relative "dbqueries"
require_relative "http"

# Discovery searches the podcast directories for a feed to subscribe to.
#
# Ported from podcasts-data/src/discovery/{mod,data,search,itunes,fyyd}.rs.
# Upstream asks every platform the settings have switched on, in parallel,
# joins the answers into one list in the order the platforms returned them,
# and folds duplicates together — a feed found twice keeps the longer
# description and the bigger episode count. With no platform switched on it
# refuses rather than returning nothing, so the page can say why.
#
# The two platforms are the ones upstream ships: fyyd's search endpoint and
# the iTunes search API, both limited to ten results.
module Discovery
  # Upstream's ALL_PLATFORM_IDS, which is also the order of the switches on
  # the discovery page.
  ALL_PLATFORM_IDS = ["fyyd.de", "itunes.apple.com"].freeze

  FYYD_ID = "fyyd.de"
  ITUNES_ID = "itunes.apple.com"

  FYYD_URL = "https://api.fyyd.de/0.2/search/podcast?count=10"
  ITUNES_URL = "https://itunes.apple.com/search?entity=podcast&limit=10"

  SearchError = Class.new(StandardError)
  # Upstream's SearchError::NoSearchPlatformsSelected.
  NoSearchPlatformsSelected = Class.new(SearchError)

  # One result, upstream's FoundPodcast.
  class FoundPodcast
    def initialize(feed:, title:, author:, description:, art:, episode_count:, last_publication:)
      @feed = feed.to_s
      @title = title.to_s
      @author = author.to_s
      @description = description.to_s
      @art = art.to_s
      @episode_count = episode_count
      @last_publication = last_publication
    end

    attr_reader :feed, :title, :author, :art
    attr_accessor :description, :episode_count, :last_publication

    # Upstream's PartialEq: roughly the same feed url, which is host, path
    # without its trailing slash, and query.
    def ==(other)
      other.is_a?(FoundPodcast) && same_feed?(other)
    end
    alias_method :eql?, :==

    # Upstream's combine: the longer description and the bigger episode count
    # win, because one platform often knows more than the other.
    def combine(other)
      if other.episode_count.to_i > episode_count.to_i
        self.episode_count = other.episode_count
      end
      if other.description.length > description.length
        self.description = other.description
      end
      self
    end

    private

      def same_feed?(other)
        [parts(feed), parts(other.feed)].then do |mine, theirs|
          if mine && theirs
            mine == theirs
          else
            feed == other.feed
          end
        end
      end

      def parts(url)
        URI.parse(url).then do |parsed|
          [parsed.host, parsed.path.to_s.sub(%r{/+\z}, ""), parsed.query]
        end
      rescue StandardError
        nil
      end
  end

  class << self
    # Upstream's search: both platforms at once, joined and deduplicated.
    def search(query)
      Dbqueries.discovery_settings.then do |settings|
        [enabled?(settings, FYYD_ID), enabled?(settings, ITUNES_ID)].then do |fyyd_on, itunes_on|
          unless fyyd_on || itunes_on
            raise NoSearchPlatformsSelected, "No Search Platform was selected."
          end

          merge(platforms(query, fyyd_on, itunes_on))
        end
      end
    end

    private

      def enabled?(settings, id) = settings.fetch(id, false) == true

      # Upstream's `join!` over the two futures: both searches run together,
      # and one that fails leaves the other's results standing.
      def platforms(query, fyyd_on, itunes_on)
        [
          Thread.new { attempt(FYYD_ID) { fyyd(query, fyyd_on) } },
          Thread.new { attempt(ITUNES_ID) { itunes(query, itunes_on) } },
        ].map(&:value)
      end

      def attempt(id, &block)
        block.call
      rescue StandardError => e
        warn "#{id} #{e.message}"
        []
      end

      # Upstream's merge_results, over the platforms in order.
      def merge(results)
        results.flatten(1).each_with_object([]) do |found, merged|
          merged.find { |other| other == found }.then do |existing|
            if existing
              existing.combine(found)
            else
              merged << found
            end
          end
        end
      end

      def fyyd(query, enabled)
        if enabled
          Http.get_json(Http.url_with_params(FYYD_URL, [["term", query]]))
            .fetch("data", [])
            .map { |podcast| from_fyyd(podcast) }
        else
          []
        end
      end

      def from_fyyd(podcast)
        FoundPodcast.new(
          feed:             podcast["xmlURL"],
          title:            podcast["title"],
          author:           podcast["author"],
          description:      podcast["description"],
          art:              podcast["smallImageURL"],
          episode_count:    podcast["episode_count"]&.to_i,
          last_publication: timestamp(podcast["lastpub"]),
        )
      end

      def itunes(query, enabled)
        if enabled
          Http.get_json(Http.url_with_params(ITUNES_URL, [["term", query]]))
            .fetch("results", [])
            .map { |podcast| from_itunes(podcast) }
        else
          []
        end
      end

      # iTunes carries no description in a search result, which is why
      # upstream leaves it empty and lets fyyd fill it in on a merge.
      def from_itunes(podcast)
        FoundPodcast.new(
          feed:             podcast["feedUrl"],
          title:            podcast["collectionName"],
          author:           podcast["artistName"],
          description:      "",
          art:              podcast["artworkUrl100"],
          episode_count:    podcast["trackCount"]&.to_i,
          last_publication: timestamp(podcast["releaseDate"]),
        )
      end

      def timestamp(value)
        if value
          Time.iso8601(value.to_s).localtime
        end
      rescue ArgumentError
        begin
          Time.parse(value.to_s).localtime
        rescue ArgumentError
          nil
        end
      end
  end
end
