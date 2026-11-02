# frozen_string_literal: true

require "set"

# Utils is the UI side's formatting and bookkeeping.
#
# Ported from podcasts-gtk/src/utils.rs: the set of shows hidden while their
# removal can still be undone, the relative time and duration strings the
# player and the episode rows print, and the size string the episode subtitle
# prints (upstream's humansize with the Windows preset and no decimals).
module Utils
  SIZE_UNITS = %w[B KiB MiB GiB TiB].freeze

  class << self
    # Upstream's ignore_show / unignore_show / get_ignored_shows: a show is
    # hidden from every view while its "Undo" toast is up, and only deleted
    # for good when the toast times out.
    def ignore_show(id) = !ignored.add?(id).nil?
    def unignore_show(id) = !ignored.delete?(id).nil?
    def ignored_shows = ignored.to_a

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
