# frozen_string_literal: true

require_relative "database"

# QueueItem is one slot of the playback queue.
#
# Ported from podcasts-data/src/models/queue_item.rs and
# podcasts-data/src/models/new_queue_item.rs. The position is a float so an
# episode can be dropped between two others without renumbering the rest, as
# the queue's drag and drop does.
class QueueItem
  def self.from_row(row) = new(row)

  def initialize(row)
    @row = row.transform_keys(&:to_s)
  end

  def id = @row["id"]
  def episode_id = @row["episode_id"]
  def position = @row["position"].to_f
  def to_h = @row.dup

  def position=(value)
    @row["position"] = value.to_f
    Database.connection.update("queue", id, @row)
    value
  end
end
