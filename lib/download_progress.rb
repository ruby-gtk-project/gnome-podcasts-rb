# frozen_string_literal: true

require "adwaita"
require_relative "download_manager"

# DownloadProgress is the thin bar under an episode row while it downloads.
#
# Ported from podcasts-gtk/src/widgets/download_progress_bar.rs: a Bin holding
# a ProgressBar that is invisible until the episode is downloading, timeouts
# that follow the shared `Progress` from the main loop, a `total_size` taken
# from the response's Content-Length rather than from the feed, and a `cancel`
# that asks the download to stop and waits for it to actually go away.
#
# Upstream exposes `local_size` and `total_size` as GObject properties and the
# episode row binds a label to them; the port keeps them as plain accessors
# with a callback, because a custom property means subclassing GLib::Object in
# these bindings.
class DownloadProgress
  POLL_INTERVAL = 100
  FINISH_INTERVAL = 250

  def initialize
    @local_size = 0
    @total_size = 0
    @state_callbacks = []
    @size_callbacks = []
    @listening = false
  end

  attr_reader :episode_id, :local_size, :total_size

  def build
    bin.tap do |root|
      root.child = progress_bar
    end
  end

  # Upstream's init(episode_id).
  def init(episode_id)
    @episode_id = episode_id
    self
  end

  # Fires whenever the bar appears or disappears, which is what tells the
  # episode row to recompute its buttons.
  def on_state_change(&block)
    @state_callbacks << block
  end

  # Fires on every progress tick, with the bytes downloaded and the total.
  def on_size_change(&block)
    @size_callbacks << block
  end

  def downloading? = DownloadManager.active?(episode_id)

  # Upstream's check_if_downloading: answer whether this episode is
  # downloading, and if it is, put the bar up and start following it.
  def check_if_downloading
    downloading?.tap do |active|
      if active && !@listening
        start_listening
      end
    end
  end

  # Upstream's cancel.
  def cancel
    DownloadManager.progress_for(episode_id).then do |progress|
      if progress
        progress.cancel
      end
    end
  end

  def bin
    @bin ||= Adwaita::Bin.new.tap do |root|
      root.margin_start = 6
      root.margin_end = 6
    end
  end

  def progress_bar
    @progress_bar ||= Gtk::ProgressBar.new.tap do |bar|
      bar.visible = false
      bar.hexpand = true
      bar.pulse_step = 0.0
    end
  end

  private

    def start_listening
      @listening = true
      progress_bar.visible = true
      notify_state

      GLib::Timeout.add(POLL_INTERVAL) { tick }
    end

    # One turn of the main loop's watch over the download.
    def tick
      DownloadManager.progress_for(episode_id).then do |progress|
        if progress
          follow(progress)
          true
        else
          finish
          false
        end
      end
    end

    def follow(progress)
      @local_size = progress.downloaded_bytes
      @total_size = progress.total_bytes
      progress_bar.fraction = progress.fraction
      @size_callbacks.each { |callback| callback.call(@local_size, @total_size) }
    end

    def finish
      progress_bar.visible = false
      progress_bar.fraction = 0.0
      @listening = false
      notify_state
    end

    def notify_state
      @state_callbacks.each { |callback| callback.call(progress_bar.visible?) }
    end
end
