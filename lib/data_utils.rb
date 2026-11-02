# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "dbqueries"
require_relative "xdg_dirs"

# DataUtils keeps the files on disk in step with the rows.
#
# Ported from podcasts-data/src/utils.rs: the download and cover directories, a
# hash for cache file names, and the three checks upstream runs at startup —
# clear `local_uri` for files that went away, delete played episodes past their
# cleanup age, and drop stale covers.
module DataUtils
  class << self
    # Upstream's get_download_dir: one directory per show, by title.
    def download_dir(show_title)
      File.join(XdgDirs.downloads, sanitize(show_title)).tap do |dir|
        FileUtils.mkdir_p(dir)
      end
    end

    # Upstream's get_cover_dir.
    def cover_dir(show_title)
      File.join(XdgDirs.cache, sanitize(show_title)).tap do |dir|
        FileUtils.mkdir_p(dir)
      end
    end

    # Upstream's calculate_hash, used for cache file names. The algorithm
    # differs — Rust's DefaultHasher is not a stable format — but the use does
    # not: a short, stable name for a uri.
    def hash(value) = Digest::SHA256.hexdigest(value.to_s)[0, 16]

    # Upstream's delete_local_content: remove the downloaded file and forget
    # it on the row.
    def delete_local_content(episode)
      episode.local_uri.then do |uri|
        if uri.nil?
          warn "Episode #{episode.id} has no local file to delete"
        else
          remove_file(episode, uri)
        end
      end
    end

    # Upstream's delete_show: drop the feed's rows and its files.
    def delete_show(show)
      Dbqueries.remove_feed(show)
      [download_dir(show.title), cover_dir(show.title)].each do |dir|
        FileUtils.rm_rf(dir)
      end
    end

    # Upstream's checkup, run from the application's startup.
    def checkup(cleanup_date)
      download_checker
      played_cleaner(cleanup_date)
      cover_cleaner(cleanup_date)
    end

    private

      # A show title becomes a directory name, so the separators have to go.
      def sanitize(title) = title.to_s.tr("/", "_").strip

      def remove_file(episode, uri)
        if File.exist?(uri)
          FileUtils.rm_f(uri)
        end
        episode.local_uri = nil
      end

      # Episodes whose file is gone are no longer downloaded.
      def download_checker
        Dbqueries.downloaded_episodes
          .reject { |episode| File.exist?(episode.local_uri.to_s) }
          .each { |episode| episode.local_uri = nil }
      end

      # Played episodes older than the cleanup date lose their file.
      def played_cleaner(cleanup_date)
        Dbqueries.played_cleaner_episodes
          .select { |episode| episode.played < cleanup_date }
          .each { |episode| delete_local_content(episode) }
      end

      # Cached covers untouched since the cleanup date go away.
      def cover_cleaner(cleanup_date)
        Dir.glob(File.join(XdgDirs.cache, "*", "*")).each do |path|
          if File.file?(path) && File.mtime(path).utc < cleanup_date
            FileUtils.rm_f(path)
          end
        end
      end
  end
end
