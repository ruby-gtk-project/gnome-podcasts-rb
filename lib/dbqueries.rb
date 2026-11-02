# frozen_string_literal: true

require_relative "database"
require_relative "episode"
require_relative "queue_item"
require_relative "show"
require_relative "source"

# Dbqueries is every read and write the app makes against the row store.
#
# Ported from podcasts-data/src/dbqueries.rs. Upstream's queries are diesel
# expressions against SQLite; here they are selections over the row arrays
# `Database` keeps, in the same order, with the same filters and the same
# semantics — including the `LIKE '%text%'` search, which becomes a
# case-insensitive substring match.
module Dbqueries
  # The filter the Shows grid builds from its filter menu.
  #
  # Upstream's ShowFilter translates to a `shows` query with subselects over
  # `episodes`; the three fields mean the same thing here.
  class ShowFilter
    def initialize(any_downloaded: nil, completed: nil, title_or_description: nil, reverse_order: false)
      @any_downloaded = any_downloaded
      @completed = completed
      @title_or_description = title_or_description
      @reverse_order = reverse_order
    end

    attr_reader :any_downloaded, :completed, :title_or_description, :reverse_order

    def default? = any_downloaded.nil? && completed.nil? && title_or_description.nil? && !reverse_order

    def apply(shows)
      sort(shows.select { |show| matches?(show) })
    end

    private

      def sort(shows)
        shows.sort_by { |show| show.title.downcase }.then do |sorted|
          if reverse_order
            sorted.reverse
          else
            sorted
          end
        end
      end

      def matches?(show)
        matches_text?(show) && matches_completed?(show) && matches_downloaded?(show)
      end

      def matches_text?(show)
        if title_or_description.nil?
          true
        else
          Dbqueries.like?(show.title, title_or_description) ||
            Dbqueries.like?(show.description, title_or_description)
        end
      end

      # Completed means no unplayed episodes left.
      def matches_completed?(show)
        if completed.nil?
          true
        else
          Dbqueries.episodes_of(show.id).any? { |ep| !ep.played? }.then do |has_unplayed|
            completed == !has_unplayed
          end
        end
      end

      def matches_downloaded?(show)
        if any_downloaded.nil?
          true
        else
          Dbqueries.episodes_of(show.id).any?(&:downloaded?) == any_downloaded
        end
      end
  end

  # The filter the Home and show pages build from their filter menu. Ported
  # from upstream's EpisodeFilter.
  class EpisodeFilter
    def initialize(downloaded: nil, played: nil, search: nil, reverse_order: false)
      @downloaded = downloaded
      @played = played
      @search = search
      @reverse_order = reverse_order
    end

    attr_reader :downloaded, :played, :reverse_order
    attr_accessor :search

    def default? = downloaded.nil? && played.nil? && search.nil? && !reverse_order

    def apply(episodes)
      sort(episodes.select { |episode| matches?(episode) })
    end

    private

      def sort(episodes)
        episodes.sort_by { |episode| episode.epoch.to_i }.then do |sorted|
          if reverse_order
            sorted
          else
            sorted.reverse
          end
        end
      end

      def matches?(episode)
        matches_downloaded?(episode) && matches_played?(episode) && matches_search?(episode)
      end

      def matches_downloaded?(episode)
        if downloaded.nil?
          true
        else
          episode.downloaded? == downloaded
        end
      end

      def matches_played?(episode)
        if played.nil?
          true
        else
          episode.played? == played
        end
      end

      def matches_search?(episode)
        if search.nil?
          true
        else
          Dbqueries.like?(episode.title, search) || Dbqueries.like?(episode.description, search)
        end
      end
  end

  class << self
    def db = Database.connection

    # Upstream's user_input_to_like_query plus the LIKE itself: a substring
    # match, and SQLite's LIKE is case-insensitive for ASCII.
    def like?(haystack, needle)
      haystack.to_s.downcase.include?(needle.to_s.strip.downcase)
    end

    # Sources, ordered the way upstream orders them: by etag then last
    # modified, so the ones that have never been fetched come first.
    def sources
      db.rows("source")
        .sort_by { |row| [row["http_etag"].to_s, row["last_modified"].to_s] }
        .map { |row| Source.from_row(row) }
    end

    def podcasts
      db.rows("shows").map { |row| Show.from_row(row) }.sort_by { |show| show.title.downcase }
    end

    def podcasts_filter(filter_ids, filter)
      filter.apply(podcasts.reject { |show| filter_ids.include?(show.id) })
    end

    def podcast_from_id(id)
      db.find("shows", id).then do |row|
        unless row
          raise KeyError, "no show with id #{id}"
        end

        Show.from_row(row)
      end
    end

    def podcast_from_source_id(source_id)
      db.rows("shows").find { |row| row["source_id"] == source_id }.then do |row|
        unless row
          raise KeyError, "no show for source #{source_id}"
        end

        Show.from_row(row)
      end
    end

    def podcast_from_uri(uri)
      source_from_uri(uri).then { |source| [source, podcast_from_source_id(source.id)] }
    end

    def source_from_uri(uri)
      db.rows("source").find { |row| row["uri"] == uri }.then do |row|
        unless row
          raise KeyError, "no source with uri #{uri}"
        end

        Source.from_row(row)
      end
    end

    def source_from_id(id)
      db.find("source", id).then do |row|
        unless row
          raise KeyError, "no source with id #{id}"
        end

        Source.from_row(row)
      end
    end

    def source_exists?(uri) = db.rows("source").any? { |row| row["uri"] == uri }
    def podcast_exists?(source_id) = db.rows("shows").any? { |row| row["source_id"] == source_id }

    def episodes
      db.rows("episodes").map { |row| Episode.from_row(row) }.sort_by { |ep| -ep.epoch.to_i }
    end

    def episodes_of(show_id)
      db.rows("episodes")
        .select { |row| row["show_id"] == show_id }
        .map { |row| Episode.from_row(row) }
    end

    def episode_from_id(id)
      db.find("episodes", id).then do |row|
        unless row
          raise KeyError, "no episode with id #{id}"
        end

        Episode.from_row(row)
      end
    end

    # One page of the Home view's episode list, newest first unless the filter
    # reverses the order.
    def episodes_widgets_page(filter_ids, filter, offset, limit)
      episodes.reject { |ep| filter_ids.include?(ep.show_id) }.then do |rows|
        filter.apply(rows).drop(offset).take(limit)
      end
    end

    def pd_episodes(show) = episodes_of(show.id).sort_by { |ep| -ep.epoch.to_i }
    def pd_episodes_count(show) = episodes_of(show.id).length
    def pd_episode_widgets(show, filter) = filter.apply(episodes_of(show.id))
    def pd_unplayed_episodes(show) = pd_episodes(show).reject(&:played?)

    def downloaded_episodes = episodes.select(&:downloaded?)
    def played_cleaner_episodes = episodes.select { |ep| ep.played? && ep.downloaded? }

    # Upstream matches an episode by guid when the feed gives one, and falls
    # back to the title inside the same show.
    def episode_exists?(guid, title, show_id)
      !find_episode(guid, title, show_id).nil?
    end

    def episode(guid, title, show_id)
      find_episode(guid, title, show_id).then do |row|
        unless row
          raise KeyError, "no episode #{title.inspect} in show #{show_id}"
        end

        Episode.from_row(row)
      end
    end

    def episodes_populated?(filter_show_ids)
      db.rows("episodes").any? { |row| !filter_show_ids.include?(row["show_id"]) }
    end

    def podcasts_populated?(filter_ids)
      db.rows("shows").any? { |row| !filter_ids.include?(row["id"]) }
    end

    def source_populated?(filter_ids)
      db.rows("source").any? { |row| !filter_ids.include?(row["id"]) }
    end

    # Marks every unplayed episode of a show played, as the show menu's "Mark
    # all as played" does, and answers how many rows changed.
    def update_none_to_played_now(show)
      Time.now.utc.to_i.then do |now|
        pd_unplayed_episodes(show).each { |ep| ep.set_played(now) }.length
      end
    end

    def remove_feed(show)
      episode_row_ids(show.id).then do |episode_ids|
        db.delete("source", show.source_id)
        db.delete("shows", show.id)
        db.delete_where("episodes") { |row| row["show_id"] == show.id }
        db.delete_where("queue") { |row| episode_ids.include?(row["episode_id"]) }
      end
    end

    def remove_source(source) = db.delete("source", source.id)

    def remove_feed_by_uri(uri)
      source_from_uri(uri).then { |source| remove_feed(podcast_from_source_id(source.id)) }
    end

    # The queue, in playback order.
    def queue
      db.rows("queue")
        .sort_by { |row| row["position"].to_f }
        .map { |row| QueueItem.from_row(row) }
    end

    def queue_item(episode_id)
      db.rows("queue").find { |row| row["episode_id"] == episode_id }.then do |row|
        unless row
          raise KeyError, "episode #{episode_id} is not in the queue"
        end

        QueueItem.from_row(row)
      end
    end

    def queued?(episode_id) = db.rows("queue").any? { |row| row["episode_id"] == episode_id }

    def next_item_in_queue(item)
      queue.find { |other| other.position > item.position }
    end

    def add_episode_to_queue(episode_id)
      unless queued?(episode_id)
        queue.last.then do |last|
          position = 0.0
          if last
            position = last.position + 1.0
          end
          db.insert("queue", "episode_id" => episode_id, "position" => position)
        end
      end
    end

    def remove_queue_item(item) = db.delete("queue", item.id)

    def first_position_in_queue?(episode_id)
      queue.first.then { |first| !first.nil? && first.episode_id == episode_id }
    end

    def last_position_in_queue?(episode_id)
      queue.last.then { |last| !last.nil? && last.episode_id == episode_id }
    end

    def move_episode_up_in_queue(episode_id)
      queue.then do |items|
        items.index { |item| item.episode_id == episode_id }.then do |index|
          if index && index.positive?
            swap_positions(items[index], items[index - 1])
          end
        end
      end
    end

    def move_episode_down_in_queue(episode_id)
      queue.then do |items|
        items.index { |item| item.episode_id == episode_id }.then do |index|
          if index && index < items.length - 1
            swap_positions(items[index], items[index + 1])
          end
        end
      end
    end

    # Drops an episode next to another one, taking the midpoint between the
    # target and its neighbour exactly as upstream does.
    def move_episode_to_position_in_queue(episode_to_move, target_episode, is_bottom_target)
      unless episode_to_move == target_episode
        queue.then do |items|
          target = items.find { |item| item.episode_id == target_episode }
          if target
            db.update(
              "queue",
              queue_item(episode_to_move).id,
              "position" => new_position(
                items,
                target,
                episode_to_move,
                is_bottom_target,
              ),
            )
          end
        end
      end
    end

    def queue_index_after_move(episode_id)
      queue.index { |item| item.episode_id == episode_id }
    end

    def discovery_settings
      db.rows("discovery_settings").to_h { |row| [row["platform_id"], row["enabled"] == true] }
    end

    def set_discovery_setting(platform_id, value)
      db.insert("discovery_settings", "platform_id" => platform_id, "enabled" => value)
    end

    private

      def episode_row_ids(show_id)
        db.rows("episodes").select { |row| row["show_id"] == show_id }.map { |row| row["id"] }
      end

      def find_episode(guid, title, show_id)
        db.rows("episodes").select { |row| row["show_id"] == show_id }.then do |rows|
          if guid.nil?
            rows.find { |row| row["title"] == title }
          else
            rows.find { |row| row["guid"] == guid }
          end
        end
      end

      # The temporary position mirrors upstream's `i32::MIN as f64`: the swap
      # parks one row out of the way so the queue's unique position index
      # never sees two rows claiming the same slot.
      TEMP_POSITION = -2_147_483_648.0

      def swap_positions(one, other)
        one.position.then do |position|
          db.update("queue", one.id, "position" => TEMP_POSITION)
          db.update("queue", other.id, "position" => position)
          db.update("queue", one.id, "position" => other.position)
        end
      end

      def new_position(items, target, episode_to_move, is_bottom_target)
        neighbour(
          items,
          target,
          episode_to_move,
          is_bottom_target,
        ).then do |other|
          if other
            (target.position + other.position) / 2.0
          elsif is_bottom_target
            target.position + 1.0
          else
            target.position - 1.0
          end
        end
      end

      def neighbour(items, target, episode_to_move, is_bottom_target)
        items.reject { |item| item.episode_id == episode_to_move }.then do |others|
          if is_bottom_target
            others.find { |item| item.position > target.position }
          else
            others.reverse.find { |item| item.position < target.position }
          end
        end
      end
  end
end
