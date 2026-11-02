# frozen_string_literal: true

require_relative "database"

# Episode is one item of a podcast feed.
#
# Ported from podcasts-data/src/models/episode.rs. Upstream carries four
# structs over the same row — `Episode`, `EpisodeWidgetModel`,
# `EpisodeCleanerModel` and `EpisodeMinimal` — because diesel needs a struct
# per `select`. A row hash needs no narrowing, so all four collapse into this
# one class, which carries the union of their behaviour: the widget model's
# `set_played_now` / `set_unplayed`, the cleaner's `local_uri=` and the
# minimal model's identity comparison.
class Episode
  def self.from_row(row) = new(row)

  def initialize(row)
    @row = row.transform_keys(&:to_s)
  end

  def id = @row["id"]
  def title = @row["title"].to_s
  def uri = @row["uri"]
  def local_uri = @row["local_uri"]
  def description = @row["description"]
  def image_uri = @row["image_uri"]
  def guid = @row["guid"]
  def length = @row["length"]
  def duration = @row["duration"]
  def show_id = @row["show_id"]
  def play_position = @row["play_position"].to_i
  def epoch = Time.at(@row["epoch"].to_i).utc
  def to_h = @row.dup

  # `played` is a timestamp upstream, not a flag: the moment the episode was
  # marked played, or nil.
  def played
    @row["played"].then do |value|
      if value
        Time.at(value.to_i).utc
      end
    end
  end

  def played? = !@row["played"].nil?
  def downloaded? = !local_uri.nil? && !local_uri.to_s.empty?

  def local_uri=(value)
    @row["local_uri"] = value
    save
  end

  # Upstream's EpisodeWidgetModel#set_length, written once a download lands
  # and the real size of the file is known.
  def length=(value)
    @row["length"] = value.to_i
    save
  end

  def set_played(time)
    @row["played"] = time&.to_i
    save
  end

  def set_played_now = set_played(Time.now.utc)
  def set_unplayed = set_played(nil)

  def play_position=(seconds)
    @row["play_position"] = seconds.to_i
    save
  end

  # Upstream only writes the position when it moved by more than a second, so
  # a ticking player does not write a row per frame.
  def set_play_position_if_divergent(seconds)
    (seconds.to_i - play_position).abs.then do |diff|
      if diff > 1
        self.play_position = seconds
      end
    end
  end

  def save
    Database.connection.update("episodes", id, @row)
    self
  end
end
