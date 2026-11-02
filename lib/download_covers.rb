# frozen_string_literal: true

require "fileutils"
require "gdk_pixbuf2"
require "gtk4"
require "uri"
require_relative "data_utils"
require_relative "dbqueries"
require_relative "http"
require_relative "thumbnail_generator"
require_relative "xdg_dirs"

# DownloadCovers puts a show's cover art into a widget.
#
# Ported from podcasts-gtk/src/download_covers.rs. Upstream keeps a texture
# cache keyed by show and thumbnail size, a download lock per show and a load
# lock per thumbnail, and for each request works down the same ladder: the
# memory cache, the thumbnail on disk, a re-download when the cached copy is
# older than four weeks, a re-download when the thumbnail is missing although
# the original is there, and a first download when nothing is there at all. A
# cover that fails is remembered as failed, so a broken image is not fetched
# again and again.
#
# Covers live at XDG_CACHE/{show title}/cover and the thumbnails beside them
# at cover-{size}, exactly as upstream's `determin_cover_path` puts them.
#
# The shape of the concurrency is the port's, not upstream's: there is no
# tokio runtime and a GTK widget may only be touched from the main thread, so
# one worker thread drains a queue of cover jobs — which is also what gives
# upstream's "download each cover once" — and a main-loop tick turns what it
# finished into textures and hands them to the widgets that asked. Upstream's
# separate "update" path collapses into the download, because the download
# already writes into a temporary directory and renames the finished file over
# the old one.
module DownloadCovers
  # Upstream's CACHE_VALID_DURATION.
  CACHE_VALID_DURATION = 4 * 7 * 24 * 60 * 60

  # How often the main loop collects what the worker finished, and how many
  # of those turns it keeps going for after the last one arrived.
  TICK = 100
  IDLE_TICKS = 20

  # Upstream's filename_for_download: image-rs gets confused when the suffix
  # is missing or wrong, so the one the content type implies is appended.
  EXTENSIONS = {
    "image/apng" => ".png",
    "image/avif" => ".avif",
    "image/gif"  => ".gif",
    "image/jpeg" => ".jpeg",
    "image/png"  => ".png",
    "image/svg"  => ".svg",
    "image/webp" => ".webp",
  }.freeze

  FALLBACK_NAME = "tmp-donwload.bin"

  class << self
    # Upstream's load_widget_texture: the widget gets the thumbnail its scale
    # factor calls for, from the cache when it is there and from the worker
    # when it is not.
    def load_widget_texture(widget, show_id, size, set_tooltip: false)
      (ThumbnailGenerator.hidpi(size, widget.scale_factor) || ThumbnailGenerator::SIZES.last)
        .then do |thumb_size|
          if set_tooltip
            widget.tooltip_text = Dbqueries.podcast_from_id(show_id).title
          end
          deliver_or_queue(widget, [show_id, thumb_size])
        end
    rescue KeyError => e
      warn "no show to load a cover for: #{e.message}"
    end

    # Upstream's determin_cover_path. Covers are XDG_CACHE/{title}/cover and
    # thumbs are XDG_CACHE/{title}/cover-{size}.
    def cover_path(show, size = nil)
      File.join(DataUtils.cover_dir(show.title), size ? "cover-#{size}" : "cover")
    end

    # Upstream's clean_unfinished_downloads, run at startup: a part file or a
    # cover download's temporary directory left behind by a crash.
    def clean_unfinished_downloads
      Dir.glob(File.join(XdgDirs.tmp, "*")).each { |path| cleanup_entry(path) }
      Dir.glob(File.join(XdgDirs.cache, "*", "*.part")).each { |path| FileUtils.rm_f(path) }
    end

    private

      def mutex = @mutex ||= Mutex.new
      def jobs = @jobs ||= Thread::Queue.new
      def cache = @cache ||= {}
      def pending = @pending ||= {}
      def ready = @ready ||= []

      def deliver_or_queue(widget, key)
        mutex.synchronize { cache[key] }.then do |cached|
          if cached.is_a?(Gdk::Texture)
            set_texture(widget, cached)
          elsif cached.nil?
            enqueue(widget, key)
          end
        end
      end

      # Upstream's locks: a cover is only fetched once, and every widget that
      # asked for it while it was being fetched is served from the one result.
      def enqueue(widget, key)
        mutex.synchronize do
          pending.key?(key).tap do |queued|
            (pending[key] ||= []) << widget
            unless queued
              jobs.push(key)
            end
          end
        end
        start_worker
        start_tick
      end

      def start_worker
        @worker ||= Thread.new do
          loop do
            jobs.pop.then { |key| finish(key, thumbnail_for(key)) }
          end
        end
      end

      # The collector keeps running for IDLE_TICKS after the last cover
      # arrived rather than stopping the moment the queue drains. Stopping and
      # restarting it per request left a finished cover sitting in `ready` for
      # seconds at a time when the restart landed in the middle of a
      # navigation animation, and the views ask for covers in bursts anyway.
      def start_tick
        @idle_ticks = 0
        unless @ticking
          @ticking = true
          GLib::Timeout.add(TICK) { tick }
        end
      end

      def tick
        deliver_ready
        if idle?
          @idle_ticks += 1
        else
          @idle_ticks = 0
        end
        (@idle_ticks < IDLE_TICKS).tap do |keep|
          unless keep
            @ticking = false
          end
        end
      end

      def idle? = mutex.synchronize { pending.empty? } && ready.empty?

      def deliver_ready
        mutex.synchronize { ready.slice!(0, ready.length).to_a }.each do |key, path|
          deliver(key, path)
        end
      end

      def finish(key, path)
        mutex.synchronize { ready << [key, path] }
      end

      # The one place a texture is made, so GDK is only touched from the main
      # loop even though the file came off a worker thread.
      def deliver(key, path)
        texture(path).then do |made|
          mutex.synchronize do
            cache[key] = made || :failed
            pending.delete(key).to_a
          end.each do |widget|
            if made
              set_texture(widget, made)
            end
          end
        end
      end

      def texture(path)
        if path && File.exist?(path)
          Gdk::Texture.new(GdkPixbuf::Pixbuf.new(file: path))
        end
      rescue StandardError => e
        warn "Failed to load image: #{path} #{e.message}"
        nil
      end

      # Upstream's TextureWidget, implemented for Gtk::Image and
      # Gtk::Picture; both take a paintable.
      def set_texture(widget, texture)
        widget.paintable = texture
      end

      # The worker's whole job: answer the path of the thumbnail this key
      # wants, downloading and generating whatever is missing. Runs off the
      # main thread, so it touches files and rows but never a widget.
      def thumbnail_for(key)
        Dbqueries.podcast_from_id(key.first).then do |show|
          if show.image_uri.to_s.empty?
            warn "no image_uri for this show: #{show.title}"
            nil
          else
            ensure_thumbnail(show, key.last)
          end
        end
      rescue StandardError => e
        warn "Failed to load Show Cover: #{e.message}"
        nil
      end

      def ensure_thumbnail(show, size)
        [cover_path(show), cover_path(show, size)].then do |cover, thumb|
          if !show.cached_image_valid?(CACHE_VALID_DURATION)
            refresh(show, cover, thumb)
          elsif File.exist?(thumb)
            thumb
          elsif File.exist?(cover)
            # A fallback for a cache the user touched, or a download that
            # landed something no thumbnail could be made from.
            warn "Cover exists, but thumb is missing. Regenerating thumbnails!"
            if generate(show, cover) && File.exist?(thumb)
              thumb
            end
          elsif download(show, cover) && File.exist?(thumb)
            thumb
          end
        end
      end

      # The cached copy is past its four weeks: fetch a new one, and keep the
      # old one when the fetch fails.
      def refresh(show, cover, thumb)
        if download(show, cover) && File.exist?(thumb)
          thumb
        elsif File.exist?(thumb)
          thumb
        end
      end

      # Downloads into a temporary directory, generates every thumbnail from
      # what landed, and only then renames the original into place — so a
      # cover that exists can be taken to have its thumbnails.
      def download(show, cover)
        temporary_directory(show) do |dir|
          fetch(show.image_uri, dir).then do |file|
            generate(show, file).then do |generated|
              if generated
                show.update_image_cache_values
                FileUtils.mkdir_p(File.dirname(cover))
                FileUtils.mv(file, cover)
              end
              generated
            end
          end
        end
      rescue StandardError => e
        warn "Failed to download cover for #{show.title}: #{e.message}"
        false
      end

      def generate(show, path)
        ThumbnailGenerator::SIZES.to_h { |size| [size, cover_path(show, size)] }
          .then { |targets| ThumbnailGenerator.generate(path, targets) }
          .then { |written| written.length == ThumbnailGenerator::SIZES.length }
      rescue StandardError => e
        warn "Failed to write cover thumbnail for #{show.title}: #{e.message}"
        false
      end

      def temporary_directory(show, &block)
        File.join(XdgDirs.tmp, "#{show.id}-pdcover.part").then do |dir|
          FileUtils.mkdir_p(dir)
          block.call(dir)
        ensure
          FileUtils.rm_rf(dir)
        end
      end

      def fetch(url, dir)
        [].tap do |landed|
          Http.get(url) do |response|
            File.join(dir, filename_for(response, url)).then do |path|
              File.open(path, "wb") { |file| response.read_body { |chunk| file.write(chunk) } }
              landed << path
            end
          end
        end.first
      end

      def filename_for(response, url)
        EXTENSIONS.fetch(content_type(response), "").then do |extension|
          basename(url).then do |name|
            if name.empty?
              "tmp-donwload#{extension}"
            else
              "#{name}#{extension}"
            end
          end
        end
      end

      def content_type(response) = response["content-type"].to_s.split(";").first.to_s.strip.downcase

      # Upstream takes the name from the url's last path segment.
      def basename(url)
        URI.parse(url.to_s).path.to_s.split("/").last.to_s.gsub(%r{[^\w.\-]}, "_")
      rescue StandardError
        FALLBACK_NAME
      end

      def cleanup_entry(path)
        if File.file?(path) && path.end_with?(".part")
          FileUtils.rm_f(path)
        end
        if File.directory?(path) && path.include?("-pdcover.part")
          FileUtils.rm_rf(path)
        end
      end
  end
end
