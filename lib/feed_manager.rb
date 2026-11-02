# frozen_string_literal: true

require_relative "dbqueries"
require_relative "errors"
require_relative "pipeline"

# FeedManager runs feed refreshes and keeps two from running over each other.
#
# Ported from podcasts-data/src/feed_manager.rs. Upstream coalesces requests
# against the batches already in flight so a full refresh asked for twice runs
# once, reports FetchStarted / FetchDone over a channel, and runs the work on a
# tokio runtime. Here each batch is a Ruby thread, the state is a mutex-guarded
# hash of the source ids in flight, and the UI polls `running?` and
# `drain_finished` from the main loop instead of reading a channel — GTK
# callbacks only ever run on the main thread, so results cross back by polling
# rather than by touching widgets from a worker.
module FeedManager
  Batch = Struct.new(
    :id,
    :full_refresh,
    :source_ids,
    :thread,
    keyword_init: true,
  )

  # One finished feed: the source, and the error that stopped it, if any.
  Result = Struct.new(:source, :error, keyword_init: true)

  class << self
    # Refreshes every source, unless a full refresh is already running.
    # Answers false when there was nothing to do.
    def schedule_full_refresh
      if running_full_refresh? || !Dbqueries.source_populated?([])
        false
      else
        add_refresh(Dbqueries.sources, full_refresh: true)
        true
      end
    end

    # Refreshes the given sources, skipping the ones already in flight.
    def schedule_refresh(sources)
      sources.reject { |source| scheduled?(source.id) }.then do |pending|
        if pending.empty?
          false
        else
          add_refresh(pending, full_refresh: false)
          true
        end
      end
    end

    def running? = state[:batches].any?

    # Takes the finished results away, which is how the window learns a
    # refresh ended. Threads that are still working are left alone.
    def drain_finished
      synchronize do
        state[:batches].reject! { |batch| reap(batch) }
        state[:results].slice!(0, state[:results].length).to_a
      end
    end

    # Waits for every running refresh, for the specs and for a clean shutdown.
    def wait
      state[:batches].map(&:thread).each(&:join)
      drain_finished
    end

    private

      def state
        @state ||= {
          batches: [],
          results: [],
          next_id: 0,
          mutex:   Mutex.new,
        }
      end

      def synchronize(&block) = state[:mutex].synchronize(&block)

      def running_full_refresh?
        state[:batches].any?(&:full_refresh)
      end

      def scheduled?(source_id)
        state[:batches].any? { |batch| batch.source_ids.include?(source_id) }
      end

      def add_refresh(sources, full_refresh:)
        synchronize do
          state[:next_id] += 1
          state[:batches] << Batch.new(
            id:           state[:next_id],
            full_refresh: full_refresh,
            source_ids:   sources.map(&:id),
            thread:       refresh_thread(sources),
          )
        end
      end

      # The batch's worker. It only touches the row store and the results
      # list, never a widget.
      def refresh_thread(sources)
        Thread.new do
          Pipeline.run(sources).each do |result|
            synchronize { state[:results] << result }
          end
        end
      end

      def reap(batch)
        batch.thread.alive?.then do |alive|
          unless alive
            batch.thread.join
          end
          !alive
        end
      end
  end
end
