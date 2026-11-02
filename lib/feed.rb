# frozen_string_literal: true

require "time"
require_relative "database"
require_relative "errors"
require_relative "dbqueries"
require_relative "parser"
require_relative "show"
require_relative "source"
require_relative "xml_parser"

# Feed indexes a parsed RSS channel into the row store.
#
# Ported from podcasts-data/src/feed.rs together with the two insert models it
# drives, podcasts-data/src/models/new_show.rs and
# podcasts-data/src/models/new_episode.rs: the channel becomes a show row, each
# item becomes an episode row, an item that is already indexed and unchanged is
# left alone, one that changed is updated, and items that repeat a guid or
# title inside the same feed are taken to be the same episode.
class Feed
  # The default upstream uses when an item carries no pubDate.
  EPOCH_FALLBACK = "Thu, 1 Jan 1970 00:00:00 +0000"

  def initialize(channel:, source_id:)
    @channel = channel
    @source_id = source_id
  end

  attr_reader :channel, :source_id

  # Indexes the channel and its items, and answers the show.
  def index
    unless channel
      raise Errors::ParseError, "the feed carried no xml"
    end

    index_channel.tap { |show| index_channel_items(show) }
  end

  # The `<channel>` element, whether the document root is `<rss>` or the
  # channel itself.
  def channel_element
    if channel.local_name == "channel"
      channel
    else
      channel.element("channel")
    end
  end

  private

    def index_channel
      channel_element.then do |element|
        unless element
          raise Errors::ParseError, "the feed carried no channel"
        end

        Database.connection.insert("shows", show_attributes(element)).then do |row|
          Show.from_row(row)
        end
      end
    end

    def show_attributes(element)
      image_uri = show_image_uri(element)
      image_uri_hash = nil
      if image_uri
        image_uri_hash = Show.hash_uri(image_uri)
      end

      {
        "title"          => element.text_of("title").to_s,
        "link"           => Source.clean_url(element.text_of("link").to_s),
        "description"    => element.text_of("description").to_s,
        "image_uri"      => image_uri,
        "image_uri_hash" => image_uri_hash,
        "image_cached"   => Time.now.utc.to_i,
        "source_id"      => source_id,
      }
    end

    # The iTunes image first, then the RSS `<image><url>`, as upstream does.
    def show_image_uri(element)
      element.element("itunes:image")&.attribute("href").then do |itunes|
        if itunes
          itunes.strip
        else
          element.element("image")&.text_of("url")
        end
      end
    end

    def index_channel_items(show)
      channel_element.elements("item").then do |items|
        dedupe(items.filter_map { |item| episode_attributes(item, show.id) }).each do |attributes|
          index_episode(attributes)
        end
      end
    end

    # Upstream filters out later items that repeat an earlier guid or title.
    def dedupe(attributes)
      seen = {}
      attributes.select do |attrs|
        (attrs["guid"] || attrs["title"]).then do |key|
          if seen.key?(key)
            false
          else
            seen[key] = true
          end
        end
      end
    end

    # An item with no title is not an episode, which is the one case upstream
    # rejects outright.
    def episode_attributes(item, show_id)
      item.text_of("title").then do |title|
        if title.nil? || title.empty?
          nil
        else
          enclosure = item.element("enclosure")
          {
            "title"         => title,
            "uri"           => enclosure_uri(enclosure),
            "local_uri"     => nil,
            "description"   => item_description(item),
            "image_uri"     => item.element("itunes:image")&.attribute("href")&.strip,
            "epoch"         => item_epoch(item),
            "length"        => enclosure&.attribute("length").to_s[/\d+/]&.to_i,
            "duration"      => Parser.itunes_duration(item.text_of("itunes:duration")),
            "guid"          => item.text_of("guid"),
            "played"        => nil,
            "play_position" => 0,
            "show_id"       => show_id,
          }
        end
      end
    end

    def enclosure_uri(enclosure)
      enclosure&.attribute("url").then do |url|
        if url
          Source.clean_url(url)
        end
      end
    end

    # `<content:encoded>` wins over `<description>`, as upstream's
    # `item.content().or(item.description())` does.
    def item_description(item)
      item.text_of("content:encoded").then do |content|
        if content && !content.empty?
          content
        else
          item.text_of("description")
        end
      end
    end

    def item_epoch(item)
      Time.rfc2822(item.text_of("pubDate").to_s).utc.to_i
    rescue ArgumentError, TypeError
      epoch_fallback(item)
    end

    def epoch_fallback(item)
      Time.parse(item.text_of("pubDate").to_s).utc.to_i
    rescue ArgumentError, TypeError
      Time.rfc2822(EPOCH_FALLBACK).utc.to_i
    end

    # Insert, update or leave alone, which is upstream's IndexState.
    def index_episode(attributes)
      Dbqueries.episode_exists?(attributes["guid"], attributes["title"], attributes["show_id"]).then do |exists|
        if exists
          update_episode(attributes)
        else
          Database.connection.insert("episodes", attributes)
        end
      end
    end

    # An update keeps the columns the user owns — the local file, the played
    # timestamp and the play position — and refreshes the feed's own columns.
    def update_episode(attributes)
      Dbqueries.episode(attributes["guid"], attributes["title"], attributes["show_id"]).then do |old|
        attributes.reject { |key, _| %w[local_uri played play_position].include?(key) }.then do |fresh|
          if changed?(old, fresh)
            Database.connection.update("episodes", old.id, fresh)
          end
        end
      end
    end

    def changed?(old, fresh)
      old.to_h.then do |row|
        fresh.any? { |key, value| row[key] != value }
      end
    end
end
