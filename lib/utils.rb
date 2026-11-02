# frozen_string_literal: true

require "set"
require "uri"
require_relative "dbqueries"
require_relative "feed_manager"
require_relative "http"
require_relative "pipeline"
require_relative "source"

# Utils is the UI side's formatting and bookkeeping.
#
# Ported from podcasts-gtk/src/utils.rs: the set of shows hidden while their
# removal can still be undone, the relative time and duration strings the
# player and the episode rows print, the size string the episode subtitle
# prints (upstream's humansize with the Windows preset and no decimals),
# subscribing to a feed url, and the two url rewrites the discovery page needs
# before it can subscribe — an iTunes podcast page to the feed it stands for,
# and a SoundCloud user or playlist page to its RSS feed.
module Utils
  # What a subscribe attempt came to: the show it opened, or why it did not.
  Subscription = Struct.new(:show, :error, keyword_init: true)

  SIZE_UNITS = %w[B KiB MiB GiB TiB].freeze

  class << self
    # Upstream's ignore_show / unignore_show / get_ignored_shows: a show is
    # hidden from every view while its "Undo" toast is up, and only deleted
    # for good when the toast times out.
    def ignore_show(id) = !ignored.add?(id).nil?
    def unignore_show(id) = !ignored.delete?(id).nil?
    def ignored_shows = ignored.to_a


    # Upstream's subscribe: index the url as a source, fetch it, and answer
    # the show it produced. A url that produced no show un-subscribes itself
    # again, so a typo does not leave a dead source behind.
    #
    # Two things differ from upstream and both follow from the port having no
    # channel: the fetch is a direct Pipeline run rather than an awaited
    # FEED_MANAGER.refresh, because the caller already owns the thread this
    # runs on; and the outcome comes back as a Subscription for the caller to
    # apply on the main loop, where upstream pushes RefreshAllViews and
    # GoToShow — or an ErrorNotification — down the channel from here.
    def subscribe(feed)
      source_for(feed).then do |source|
        begin
          Pipeline.run([source]).each do |result|
            if result.error
              raise result.error
            end
          end
          Subscription.new(show: Dbqueries.podcast_from_source_id(source.id), error: nil)
        rescue StandardError => e
          warn "Failed to subscribe: #{feed} #{e.message}"
          auto_unsubscribe(source)
          # The message is upstream's, which names the feed and not the
          # failure, because its pipeline passes no useful error up either.
          Subscription.new(show: nil, error: "Failed to subscribe to feed: #{feed}")
        end
      end
    end

    # Upstream's itunes_to_rss: the numeric id out of an iTunes podcast url,
    # looked up for the feed url it stands for.
    def itunes_to_rss(url)
      itunes_id(url).then do |id|
        unless id
          raise Http::Error, "Failed to find an iTunes ID."
        end

        itunes_lookup(id)
      end
    end

    # Upstream's soundcloud_to_rss: turns
    # https://soundcloud.com/chapo-trap-house into
    # https://feeds.soundcloud.com/users/soundcloud:users:211911700/sounds.rss,
    # for a user or a playlist.
    def soundcloud_to_rss(url)
      soundcloud_ids(url).then do |user_id, playlist_id|
        if playlist_id
          "https://feeds.soundcloud.com/playlists/soundcloud:playlists:#{playlist_id}/sounds.rss"
        elsif user_id
          "https://feeds.soundcloud.com/users/soundcloud:users:#{user_id}/sounds.rss"
        else
          raise Http::Error, "No valid id's in soundcloud page."
        end
      end
    end

    # Upstream's relative_time, for durations that are positive.
    def relative_time(seconds)
      seconds.to_i.then do |total|
        if total < 60
          "Just now"
        else
          relative_unit(total)
        end
      end
    end

    # Upstream's format_duration: hour:minute:second past an hour, else
    # minute:second, and "-" for nothing.
    def format_duration(seconds)
      seconds.to_i.then do |total|
        if total <= 0
          "-"
        elsif total >= 3600
          format(
            "%d:%02d:%02d",
            total / 3600,
            (total % 3600) / 60,
            total % 60,
          )
        else
          format("%02d:%02d", total / 60, total % 60)
        end
      end
    end

    # The episode subtitle's "{} min", from EpisodeWidget::get_duration.
    def format_minutes(seconds)
      (seconds.to_i / 60).then do |minutes|
        if minutes.zero?
          nil
        else
          "#{minutes} min"
        end
      end
    end

    # The episode subtitle's size, from EpisodeWidget::get_size.
    def format_size(bytes)
      bytes.to_i.then do |size|
        if size <= 0
          nil
        else
          scale_size(size.to_f, 0)
        end
      end
    end

    private

      def ignored = @ignored ||= Set.new

      def source_for(feed)
        Dbqueries.source_from_uri(feed)
      rescue KeyError
        Source.from_url(feed)
      end

      # Upstream only removes the source when no show was imported from it.
      def auto_unsubscribe(source)
        Dbqueries.podcast_from_source_id(source.id)
      rescue KeyError
        Dbqueries.remove_source(source)
        warn "auto removed source that failed to import #{source.uri}"
      end

      def itunes_id(url)
        url.to_s[%r{/id([0-9]+)}, 1]&.to_i
      end

      def itunes_lookup(id)
        Http.get_json("https://itunes.apple.com/lookup?id=#{id}&entity=podcast")
          .dig("results", 0, "feedUrl")
          .then do |feed|
            unless feed
              raise Http::Error, "Failed to get url from itunes response"
            end

            feed
          end
      end

      # Upstream reads the ids out of the page's HTML, because SoundCloud
      # publishes no other way to find them.
      def soundcloud_ids(url)
        Http.get(url.to_s).then do |page|
          [
            page[%r{soundcloud://users:([0-9]+)}, 1]&.to_i,
            page[%r{soundcloud://playlists:([0-9]+)}, 1]&.to_i,
          ]
        end
      end

      def relative_unit(total)
        [
          [60 * 60, 60, "minute"],
          [24 * 60 * 60, 60 * 60, "hour"],
          [31 * 24 * 60 * 60, 24 * 60 * 60, "day"],
          [365 * 24 * 60 * 60, 30 * 24 * 60 * 60, "month"],
        ].find { |limit, _, _| total < limit }.then do |match|
          if match
            plural(total / match[1], match[2])
          else
            plural(total / (365 * 24 * 60 * 60), "year")
          end
        end
      end

      def plural(count, unit)
        if count == 1
          "#{count} #{unit} ago"
        else
          "#{count} #{unit}s ago"
        end
      end

      def scale_size(size, unit)
        if size < 1024 || unit == SIZE_UNITS.length - 1
          "#{size.round} #{SIZE_UNITS[unit]}"
        else
          scale_size(size / 1024, unit + 1)
        end
      end
  end
end
