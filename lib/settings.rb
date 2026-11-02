# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "xdg_dirs"

# Settings holds the keys of upstream's org.gnome.Podcasts GSettings schema.
#
# Ported from podcasts-gtk/src/settings.rs and
# podcasts-gtk/resources/org.gnome.Podcasts.gschema.xml.in: the same eight keys
# with the same defaults, the same `timePeriods` enum, and the same three
# helpers — the window geometry that is restored on start and written on close,
# the auto-refresh interval, and the cleanup cut-off date.
#
# Upstream reads them through GSettings, which needs a schema compiled into the
# system's glib-2.0/schemas directory; needing an install step before the app
# can run from a checkout is worse than the alternative, so the same keys live
# in a small JSON file under XDG_CONFIG_HOME, with the same defaults and the
# same clamped ranges.
class Settings
  # The schema's `timePeriods` enum, in seconds.
  TIME_PERIODS = {
    "seconds" => 1,
    "minutes" => 60,
    "hours"   => 60 * 60,
    "days"    => 24 * 60 * 60,
    "weeks"   => 7 * 24 * 60 * 60,
    "months"  => 30 * 24 * 60 * 60,
  }.freeze

  DEFAULTS = {
    "persist-window-geometry-height"    => 640,
    "persist-window-geometry-width"     => 860,
    "persist-window-geometry-maximized" => false,
    "refresh-interval"                  => true,
    "refresh-interval-time"             => 1,
    "refresh-interval-period"           => "hours",
    "refresh-on-startup"                => true,
    "cleanup-age-time"                  => 2,
    "cleanup-age-period"                => "days",
  }.freeze

  # The schema's `range min="1" max="100"` on the two time keys.
  TIME_RANGE = (1..100)

  def initialize(path: nil)
    @path = path || default_path
    @values = DEFAULTS.merge(read)
  end

  attr_reader :path

  def [](key) = @values.fetch(key.to_s, DEFAULTS[key.to_s])

  def []=(key, value)
    @values[key.to_s] = clamp(key.to_s, value)
    write
    value
  end

  DEFAULTS.each_key do |key|
    define_method(key.tr("-", "_")) { self[key] }
    define_method(:"#{key.tr('-', '_')}=") { |value| self[key] = value }
  end

  # Upstream's settings::time_period_to_duration, in seconds.
  def self.time_period_to_duration(time, period)
    time.to_i * TIME_PERIODS.fetch(period.to_s, 1)
  end

  # Upstream's settings::get_refresh_interval.
  def refresh_interval_seconds
    Settings.time_period_to_duration(self["refresh-interval-time"], self["refresh-interval-period"])
  end

  # Upstream's settings::get_cleanup_date: episodes played before this are
  # garbage collected from the disk.
  def cleanup_date
    Time.now.utc - Settings.time_period_to_duration(
      self["cleanup-age-time"],
      self["cleanup-age-period"],
    )
  end

  # Upstream's WindowGeometry::from_settings(...).apply(window).
  def apply_to(window)
    if self["persist-window-geometry-width"].to_i.positive? &&
        self["persist-window-geometry-height"].to_i.positive?
      window.set_default_size(
        self["persist-window-geometry-width"],
        self["persist-window-geometry-height"],
      )
    end

    if self["persist-window-geometry-maximized"]
      window.maximize
    end
  end

  # Upstream's WindowGeometry::from_window(...).write(settings), called from
  # the window's close handler.
  def remember(window)
    @values["persist-window-geometry-maximized"] = window.maximized?
    unless window.maximized?
      @values["persist-window-geometry-width"] = window.default_width
      @values["persist-window-geometry-height"] = window.default_height
    end
    write
  end

  private

    def clamp(key, value)
      if %w[refresh-interval-time cleanup-age-time].include?(key)
        value.to_i.clamp(TIME_RANGE.first, TIME_RANGE.last)
      else
        value
      end
    end

    def default_path = File.join(XdgDirs.config, "settings.json")

    def read
      File.exist?(@path).then do |exists|
        if exists
          JSON.parse(File.read(@path))
        else
          {}
        end
      end
    rescue JSON::ParserError => e
      warn "Error parsing #{@path}: #{e.message}"
      {}
    end

    def write
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate(@values))
    end
end
