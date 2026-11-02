# frozen_string_literal: true

require "fileutils"

# XdgDirs is where the app keeps its files.
#
# Ported from the `xdg_dirs` module of podcasts-data/src/lib.rs, which wraps
# the `xdg` crate's BaseDirectories with the "gnome-podcasts" prefix. The
# prefix here is "gnome-podcasts-rb", so the port and an installed upstream do
# not fight over the same downloads.
module XdgDirs
  PREFIX = "gnome-podcasts-rb"

  class << self
    def data = directory(ENV.fetch("XDG_DATA_HOME", File.expand_path("~/.local/share")))
    def config = directory(ENV.fetch("XDG_CONFIG_HOME", File.expand_path("~/.config")))
    def cache = directory(ENV.fetch("XDG_CACHE_HOME", File.expand_path("~/.cache")))
    def downloads = subdirectory("Downloads")
    def tmp = subdirectory("tmp")

    private

      def directory(base)
        File.join(base, PREFIX).tap { |path| FileUtils.mkdir_p(path) }
      end

      def subdirectory(name)
        File.join(data, name).tap { |path| FileUtils.mkdir_p(path) }
      end
  end
end
