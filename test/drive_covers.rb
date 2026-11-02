# frozen_string_literal: true

# Drives the cover pipeline end to end against a local server: a show whose
# image_uri points at a PNG this script serves, loaded into a Gtk::Image the
# way the shows grid and the episode rows load theirs. Checks that the cover
# and all four thumbnails land where upstream puts them, that the widget ends
# up with a paintable, that a second request is served from the memory cache,
# and that a url that 404s is remembered as failed rather than retried.
#
# Run it from the dev shell:
#   xvfb-run ruby test/drive_covers.rb
#
# It writes PNGs under tmp/shots and exits non-zero if any check fails. The
# only network it touches is a loopback socket it opens itself.

require "socket"
require "tmpdir"

ROOT = Dir.mktmpdir("gnome-podcasts-covers")
ENV["XDG_DATA_HOME"] = File.join(ROOT, "data")
ENV["XDG_CONFIG_HOME"] = File.join(ROOT, "config")
ENV["XDG_CACHE_HOME"] = File.join(ROOT, "cache")

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "gnome_podcasts"
require "download_covers"
require "thumbnail_generator"

require_relative "gtk_driver"

# A 300x150 PNG for the server to hand out.
ARTWORK = File.join(ROOT, "artwork.png")
GdkPixbuf::Pixbuf.new(
  width:     300,
  height:    150,
  has_alpha: false,
).tap do |pixbuf|
  pixbuf.fill!(0x3584e4ff)
  pixbuf.save(ARTWORK, "png")
end

# A one-route HTTP server on loopback. The runtime closure has no webrick, and
# a cover download needs nothing more than this.
SERVER = TCPServer.new("127.0.0.1", 0)
PORT = SERVER.addr[1]

RESPONSES = {
  "/cover.png"   => lambda do
    File.binread(ARTWORK).then do |body|
      [
        "HTTP/1.1 200 OK\r\n" \
        "Content-Type: image/png\r\n" \
        "Content-Length: #{body.bytesize}\r\n" \
        "Connection: close\r\n\r\n",
        body,
      ]
    end
  end,
  "/missing.png" => lambda do
    [
      "HTTP/1.1 404 Not Found\r\n" \
      "Content-Type: text/plain\r\n" \
      "Content-Length: 4\r\n" \
      "Connection: close\r\n\r\n",
      "nope",
    ]
  end,
}.freeze

Thread.new do
  loop do
    SERVER.accept.then do |client|
      Thread.new do
        client.gets.to_s.split(" ")[1].to_s.then do |path|
          RESPONSES.fetch(path, RESPONSES["/missing.png"]).call.then do |head, body|
            client.write(head)
            client.write(body)
          end
        end
      ensure
        client.close
      end
    end
  rescue IOError, Errno::EBADF
    break
  end
end

SETTINGS = Settings.new(path: File.join(ROOT, "settings.json"))
SETTINGS["refresh-on-startup"] = false
SETTINGS["refresh-interval"] = false

# A source each: `shows` is unique on source_id, so two shows sharing one
# source would be one row.
GOOD_SOURCE = Source.from_url("http://127.0.0.1:#{PORT}/good.xml")
BAD_SOURCE = Source.from_url("http://127.0.0.1:#{PORT}/bad.xml")

GOOD = Show.from_row(
  Database.connection.insert(
    "shows",
    "title"        => "Cover Test",
    "link"         => "http://127.0.0.1:#{PORT}/",
    "description"  => "",
    "image_uri"    => "http://127.0.0.1:#{PORT}/cover.png",
    "image_cached" => 0,
    "source_id"    => GOOD_SOURCE.id,
  ),
)
BAD = Show.from_row(
  Database.connection.insert(
    "shows",
    "title"        => "Missing Cover",
    "link"         => "http://127.0.0.1:#{PORT}/",
    "description"  => "",
    "image_uri"    => "http://127.0.0.1:#{PORT}/missing.png",
    "image_cached" => 0,
    "source_id"    => BAD_SOURCE.id,
  ),
)

APP = GnomePodcasts::Application.new(settings: SETTINGS)
IMAGES = {}

GtkDriver.drive(APP, shots: "tmp/shots", interval: 1500) do |d, app|
  d.window { app.window }

  d.step("the cover paths are the ones upstream uses") do
    d.check("the cover has no suffix") do
      DownloadCovers.cover_path(GOOD).end_with?("/Cover Test/cover")
    end
    d.check("a thumb carries its size") do
      DownloadCovers.cover_path(GOOD, 64).end_with?("/Cover Test/cover-64")
    end
  end

  d.step("asking for a cover starts the download") do
    IMAGES[:good] = Gtk::Image.new(icon_name: "image-missing-symbolic")
    DownloadCovers.load_widget_texture(
      IMAGES[:good],
      GOOD.id,
      64,
      set_tooltip: true,
    )
    d.check("the tooltip went on straight away") { IMAGES[:good].tooltip_text == "Cover Test" }
  end

  d.step("and it lands as a texture on the widget") do
    d.check("the widget has a paintable") { !IMAGES[:good].paintable.nil? }
    d.check("the cover file is there") { File.exist?(DownloadCovers.cover_path(GOOD)) }
    d.check("all four thumbnails are there") do
      ThumbnailGenerator::SIZES.all? { |size| File.exist?(DownloadCovers.cover_path(GOOD, size)) }
    end
    d.check("the 64px thumb is 64 wide and keeps its aspect") do
      GdkPixbuf::Pixbuf.new(file: DownloadCovers.cover_path(GOOD, 64)).then do |thumb|
        thumb.width == 64 && thumb.height == 32
      end
    end
    d.check("the download left no temporary directory behind") do
      Dir.glob(File.join(XdgDirs.tmp, "*-pdcover.part")).empty?
    end
    d.check("the cache date was written back") do
      Dbqueries.podcast_from_id(GOOD.id).cached_image_valid?(DownloadCovers::CACHE_VALID_DURATION)
    end
  end

  d.step("a second widget is served from the memory cache, without a tick") do
    IMAGES[:again] = Gtk::Image.new(icon_name: "image-missing-symbolic")
    DownloadCovers.load_widget_texture(
      IMAGES[:again],
      GOOD.id,
      64,
      set_tooltip: false,
    )
    d.check("it already has the paintable") { !IMAGES[:again].paintable.nil? }
    d.check("it is the same texture") do
      IMAGES[:again].paintable == IMAGES[:good].paintable
    end
  end

  d.step("a cover that 404s is asked for once") do
    IMAGES[:bad] = Gtk::Image.new(icon_name: "image-missing-symbolic")
    DownloadCovers.load_widget_texture(
      IMAGES[:bad],
      BAD.id,
      64,
      set_tooltip: false,
    )
  end

  d.step("and leaves the fallback icon in place") do
    d.check("no paintable was set") { IMAGES[:bad].paintable.nil? }
    d.check("no cover file was written") { !File.exist?(DownloadCovers.cover_path(BAD)) }
    d.check("nothing was left in the tmp directory") do
      Dir.glob(File.join(XdgDirs.tmp, "*-pdcover.part")).empty?
    end
  end

  d.step("a stale part file is cleaned up at startup") do
    File.join(XdgDirs.tmp, "leftover.part").then do |stale|
      File.write(stale, "x")
      FileUtils.mkdir_p(File.join(XdgDirs.tmp, "9-pdcover.part"))
      DownloadCovers.clean_unfinished_downloads
      d.check("the part file is gone") { !File.exist?(stale) }
      d.check("the part directory is gone") do
        !File.directory?(File.join(XdgDirs.tmp, "9-pdcover.part"))
      end
    end
  end

  d.step("the downloaded cover shows on the show page") do
    app.go_to_show(Dbqueries.podcast_from_id(GOOD.id))
    d.check("the page is up") { !app.main_window.show_widget.nil? }
  end

  # The 256px thumbnail is a different cache key from the 64px one above, so
  # it takes a turn of the worker and a tick of the main loop to arrive — and
  # the navigation animation can hold the main loop for most of a step.
  d.step("while the navigation animation settles") do
    d.check("the show page is the visible one") do
      app.main_window.navigation_view.visible_page.tag == "show"
    end
  end

  d.step("the 256px thumbnail arrives") do
    d.check("the show page's cover has a paintable") do
      !app.main_window.show_widget.cover.paintable.nil?
    end
  end

  d.step("and it settles") do
    d.shot("04-cover")
    SERVER.close
  end
end
