# frozen_string_literal: true

require_relative "errors"
require_relative "feed"

# Pipeline fetches feeds and indexes them.
#
# Ported from podcasts-data/src/pipeline.rs, which runs the chain
#
#   Source -> GET request -> update etags -> check status -> parse xml ->
#   Feed -> index show -> index episodes
#
# over every source it is given and answers one result per source, so one
# broken feed never stops the rest. A 304 is not an error here either.
#
# The results are FeedManager::Result, which `feed_manager` defines; it
# requires this file, and is the only caller.
module Pipeline
  class << self
    # Answers an array of FeedManager::Result, one per source, in order.
    def run(sources)
      sources.map { |source| index_one(source) }
    end

    private

      def index_one(source)
        source.into_feed.index
        FeedManager::Result.new(source: source, error: nil)
      rescue Errors::FeedNotModified
        FeedManager::Result.new(source: source, error: nil)
      rescue StandardError => e
        warn "Error while fetching the latest xml feed: #{source.uri} - #{e.message}"
        FeedManager::Result.new(source: source, error: e)
      end
  end
end
