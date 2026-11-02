# frozen_string_literal: true

require "net/http"
require "uri"
require "fileutils"
require "tmpdir"
require_relative "data_utils"
require_relative "dbqueries"
require_relative "errors"
# DownloadManager keeps track of the episode downloads in flight.
#
# Ported from podcasts-gtk/src/manager.rs together with the downloader it
# drives, podcasts-data/src/downloader.rs. Upstream keeps a map of episode id
# to a shared `Progress`, spawns the download on its tokio runtime, writes into
# a temp file and moves it into the show's download directory on success, names
# the file after the episode id with an extension taken from the response's
# content type, and then writes the local path and the real size back onto the
# row.
#
# Here each download is a Ruby thread and `Progress` is a mutex-guarded struct
# the UI polls from the main loop, because a GTK widget may only be touched
# from the main thread.
module DownloadManager
  # The extensions upstream's mime_guess lookup produces for the content types
  # podcast enclosures actually use.
  EXTENSIONS = {
    "audio/mpeg"      => "mp3",
    "audio/mp3"       => "mp3",
    "audio/mp4"       => "m4a",
    "audio/x-m4a"     => "m4a",
    "audio/aac"       => "aac",
    "audio/ogg"       => "ogg",
    "audio/opus"      => "opus",
    "audio/vorbis"    => "ogg",
    "audio/flac"      => "flac",
    "audio/x-wav"     => "wav",
    "audio/wav"       => "wav",
    "video/mp4"       => "mp4",
    "video/quicktime" => "mov",
    "video/x-m4v"     => "m4v",
  }.freeze

  MAX_REDIRECTS = 5

  # Upstream's manager::Progress: the shared state a download writes and the
  # progress bar reads.
  class Progress
    def initialize
      @mutex = Mutex.new
      @total_bytes = 0
      @downloaded_bytes = 0
      @cancel = false
    end

    def total_bytes = @mutex.synchronize { @total_bytes }
    def downloaded_bytes = @mutex.synchronize { @downloaded_bytes }
    def cancelled? = @mutex.synchronize { @cancel }
    def cancel = @mutex.synchronize { @cancel = true }
    def total_bytes=(value)
      @mutex.synchronize { @total_bytes = value.to_i }
    end

    def downloaded_bytes=(value)
      @mutex.synchronize { @downloaded_bytes = value.to_i }
    end

    # Upstream's get_fraction, capped at 1.0, and 0.0 while the size is still
    # unknown rather than NaN.
    def fraction
      @mutex.synchronize do
        if @total_bytes.zero?
          0.0
        else
          (@downloaded_bytes.to_f / @total_bytes).clamp(0.0, 1.0)
        end
      end
    end
  end

  class << self
    # Upstream's manager::add: start a download and remember its progress
    # under the episode id.
    def add(episode_id)
      if active?(episode_id)
        active.fetch(episode_id)
      else
        Progress.new.tap do |progress|
          mutex.synchronize { active[episode_id] = progress }
          download_thread(episode_id, progress)
        end
      end
    end

    def active?(episode_id) = mutex.synchronize { active.key?(episode_id) }
    def progress_for(episode_id) = mutex.synchronize { active[episode_id] }
    def active_count = mutex.synchronize { active.length }

    # The error of the last failed download, taken away by the reader; the
    # window turns it into the toast upstream sends as an ErrorNotification.
    def take_errors
      mutex.synchronize { errors.slice!(0, errors.length).to_a }
    end

    # Waits for every download, for the specs and for shutdown.
    def wait
      threads.dup.each { |thread| thread.join }
      threads.clear
    end

    private

      def mutex = @mutex ||= Mutex.new
      def active = @active ||= {}
      def errors = @errors ||= []
      def threads = @threads ||= []

      def download_thread(episode_id, progress)
        Thread.new do
          begin
            download(episode_id, progress)
          rescue StandardError => e
            mutex.synchronize { errors << "Download failed: #{e.message}" }
          ensure
            mutex.synchronize { active.delete(episode_id) }
          end
        end.tap { |thread| threads << thread }
      end

      # Upstream's downloader::get_episode.
      def download(episode_id, progress)
        Dbqueries.episode_from_id(episode_id).then do |episode|
          unless episode.uri
            raise Errors::DownloadError, "episode #{episode_id} has no audio file"
          end

          forget_missing_file(episode)
          unless episode.downloaded?
            store(episode, fetch_into(episode, progress))
          end
        end
      end

      # A local_uri that points nowhere is cleared, as upstream does before it
      # starts over.
      def forget_missing_file(episode)
        if episode.local_uri && !File.exist?(episode.local_uri)
          episode.local_uri = nil
        end
      end

      def store(episode, path)
        episode.local_uri = path
        # Over-write the episode length with the real size of the file, as
        # upstream does once the download lands.
        episode.length = File.size(path)
      end

      # Downloads into a temp file and moves it next to the show's other
      # episodes, named after the episode id.
      def fetch_into(episode, progress)
        DataUtils.download_dir(Dbqueries.podcast_from_id(episode.show_id).title).then do |dir|
          Dir.mktmpdir("temp_download", XdgDirs.cache) do |tmp|
            File.join(tmp, "temp.part").then do |part|
              extension = stream_to(part, episode.uri, progress)
              move(part, File.join(dir, "#{episode.id}.#{extension}"))
            end
          end
        end
      end

      def move(part, target)
        FileUtils.mv(part, target)
        target
      end

      # Streams the response body into `path` and answers the extension the
      # content type implies. `Net::HTTP#request` answers the response rather
      # than the block's value, so the extension comes back in a box.
      def stream_to(path, url, progress)
        [].tap do |extension|
          request(url) do |response|
            progress.total_bytes = response["content-length"].to_i
            extension << extension_for(response["content-type"])
            write_body(response, path, progress)
          end
        end.first
      end

      def write_body(response, path, progress)
        File.open(path, "wb") do |file|
          response.read_body do |chunk|
            if progress.cancelled?
              raise Errors::DownloadError, "download cancelled"
            end

            file.write(chunk)
            progress.downloaded_bytes = file.size
          end
        end
      end

      def extension_for(content_type)
        content_type.to_s.split(";").first.to_s.strip.downcase.then do |type|
          EXTENSIONS.fetch(type, "unknown")
        end
      end

      # A plain GET with the redirects upstream's http client follows for it.
      def request(url, redirects: MAX_REDIRECTS, &block)
        URI.parse(url).then do |parsed|
          Net::HTTP.start(
            parsed.host,
            parsed.port,
            use_ssl:      parsed.scheme == "https",
            open_timeout: 20,
            read_timeout: 120,
          ) do |http|
            http.request(get(parsed)) do |response|
              follow(
                response,
                parsed,
                redirects,
                &block
              )
            end
          end
        end
      end

      def follow(response, parsed, redirects, &block)
        if response.is_a?(Net::HTTPRedirection) && redirects.positive?
          request(URI.join(parsed, response["location"]).to_s, redirects: redirects - 1, &block)
        elsif response.is_a?(Net::HTTPSuccess)
          block.call(response)
        else
          raise Errors::DownloadError, "unexpected response #{response.code} for #{parsed}"
        end
      end

      def get(parsed)
        Net::HTTP::Get.new(parsed.request_uri).tap do |http_get|
          http_get["User-Agent"] = Source::USER_AGENT
        end
      end
  end
end
