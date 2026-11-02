# frozen_string_literal: true

require "digest"
require_relative "database"

# Show is a podcast feed's channel: the thing the Shows grid lists and the show
# page shows.
#
# Ported from podcasts-data/src/models/show.rs. Upstream splits the row into
# `Show` and the narrower `ShowCoverModel` because diesel wants one struct per
# `select`; a Ruby row hash needs no narrowing, so the cover model's behaviour
# (`is_cached_image_valid`, `update_image_cached`, `update_image_cache_values`)
# lives here on the one class.
class Show
  # Upstream's ShowCoverModel::is_cached_image_valid takes the validity window
  # from the caller; every caller passes a day.
  IMAGE_CACHE_VALID_FOR = 24 * 60 * 60

  def self.from_row(row) = new(row)

  def initialize(row)
    @row = row.transform_keys(&:to_s)
  end

  def id = @row["id"]
  def title = @row["title"].to_s
  def link = @row["link"].to_s
  def description = @row["description"].to_s
  def image_uri = @row["image_uri"]
  def image_uri_hash = @row["image_uri_hash"]
  def source_id = @row["source_id"]
  def image_cached = Time.at(@row["image_cached"].to_i).utc
  def to_h = @row.dup

  # The hash upstream stores alongside the image uri, so a changed feed image
  # invalidates the cached file even when the uri's cache is still fresh.
  def self.hash_uri(uri) = Digest::SHA256.hexdigest(uri.to_s)[0, 16]

  def cached_image_valid?(valid_for = IMAGE_CACHE_VALID_FOR)
    (Time.now.utc - image_cached) < valid_for
  end

  # Marks the cached cover as refreshed now.
  def update_image_cached
    @row["image_cached"] = Time.now.utc.to_i
    save
  end

  # Re-points the cover cache at the current image uri: the hash follows the
  # uri, and the timestamp is reset so a changed uri re-downloads.
  def update_image_cache_values
    @row["image_uri_hash"] = nil
    if image_uri
      @row["image_uri_hash"] = Show.hash_uri(image_uri)
    end
    update_image_cached
  end

  def save
    Database.connection.update("shows", id, @row)
    self
  end
end
