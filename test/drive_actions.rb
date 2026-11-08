# frozen_string_literal: true

# Drives the parts of the app the other drive_*.rb scripts do not reach:
# the window/app actions and their accelerators, the episode and show
# context menus' individual actions (go to show, copy url, mark unplayed,
# download, delete, unsubscribe), the main hamburger menu's structure, an
# OPML import, and ReadMoreLabel's expand button.
#
# Run it from the dev shell:
#   xvfb-run ruby test/drive_actions.rb
#
# It writes PNGs under tmp/shots and exits non-zero if any check fails. The
# only network it touches is a loopback socket it opens itself, for the
# episode download.

require "socket"
require "tmpdir"

ROOT = Dir.mktmpdir("gnome-podcasts-actions")
ENV["XDG_DATA_HOME"] = File.join(ROOT, "data")
ENV["XDG_CONFIG_HOME"] = File.join(ROOT, "config")
ENV["XDG_CACHE_HOME"] = File.join(ROOT, "cache")

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "gnome_podcasts"
require "feed"
require "opml"
require "xml_parser"
require "episode_menu"
require "show_menu"
require "main_menu"
require "read_more_label"

require_relative "gtk_driver"

FIXTURE = File.expand_path("feeds/intercepted.xml", __dir__)
SOURCE = Source.from_url("https://example.com/intercepted.xml")
SHOW = Feed.new(channel: XmlParser.parse(File.read(FIXTURE)), source_id: SOURCE.id).index
EPISODES = Dbqueries.episodes_of(SHOW.id).sort_by { |episode| -episode.epoch.to_i }

# A one-route HTTP server on loopback, serving a tiny "audio" file for the
# download action to fetch for real.
SERVER = TCPServer.new("127.0.0.1", 0)
PORT = SERVER.addr[1]
AUDIO_BODY = "ID3fake-audio-bytes"

Thread.new do
  loop do
    SERVER.accept.then do |client|
      Thread.new do
        client.gets
        client.write(
          "HTTP/1.1 200 OK\r\n" \
          "Content-Type: audio/mpeg\r\n" \
          "Content-Length: #{AUDIO_BODY.bytesize}\r\n" \
          "Connection: close\r\n\r\n#{AUDIO_BODY}",
        )
      ensure
        client.close
      end
    end
  rescue IOError, Errno::EBADF
    break
  end
end

# Give the episode under test a real, downloadable uri instead of the
# fixture's non-resolving one.
DOWNLOAD_EPISODE = EPISODES.first
Database.connection.update(
  "episodes",
  DOWNLOAD_EPISODE.id,
  "uri" => "http://127.0.0.1:#{PORT}/ep.mp3",
)

SETTINGS = Settings.new(path: File.join(ROOT, "settings.json"))
SETTINGS["refresh-on-startup"] = false
SETTINGS["refresh-interval"] = false

APP = GnomePodcasts::Application.new(settings: SETTINGS)

GtkDriver.drive(APP, shots: "tmp/shots") do |d, app|
  d.window { app.window }

  d.step("the window opens") do
    d.check("the fixture indexed 43 episodes") { EPISODES.length == 43 }
  end

  d.step("win.go-to-shows navigates there") do
    app.window.activate_action("go-to-shows", nil)
    d.check("the shows page is up") { app.main_window.content.stack.visible_child_name == "shows" }
  end

  d.step("win.go-to-queue navigates there") do
    app.window.activate_action("go-to-queue", nil)
    d.check("the queue page is up") { app.main_window.content.stack.visible_child_name == "queue" }
  end

  d.step("win.go-to-home navigates back") do
    app.window.activate_action("go-to-home", nil)
    d.check("home is up again") { app.main_window.content.stack.visible_child_name == "home" }
  end

  d.step("win.open-search opens the home search bar") do
    app.window.activate_action("open-search", nil)
    d.check("search mode is on") { app.main_window.content.home_view.search_bar.search_mode? }
  end

  d.step("win.refresh starts a refresh that watches itself to completion") do
    app.window.activate_action("refresh", nil)
    d.check("the progress bar came up") { app.main_window.progress_bar.visible? }
  end

  d.step("and the refresh finishes on its own") do
    context = GLib::MainContext.default
    100.times do
      break unless app.main_window.progress_bar.visible?

      context.iteration(false)
      sleep(0.02)
    end
    d.check("the progress bar went back down") { !app.main_window.progress_bar.visible? }
  end

  d.step("app.shortcuts presents the shortcuts dialog") do
    app.app.activate_action("shortcuts", nil)
    d.check("the window has a visible dialog") { !app.window.visible_dialog.nil? }
    d.shot("12-shortcuts")
  end

  d.step("and it closes again") do
    app.window.visible_dialog&.close
    d.check("the dialog is gone") { app.window.visible_dialog.nil? }
  end

  d.step("win.about presents the about dialog") do
    app.window.activate_action("about", nil)
    d.check("the window has a visible dialog") { !app.window.visible_dialog.nil? }
  end

  d.step("and it closes again") do
    app.window.visible_dialog&.close
    d.check("the dialog is gone") { app.window.visible_dialog.nil? }
  end

  d.step("the main hamburger menu carries upstream's two sections") do
    MainMenu.new.build.then do |model|
      d.check("it has two sections") { model.n_items == 2 }
    end
  end

  d.step("the episode menu wires go-to-show, copy-url and mark-unplayed") do
    app.mark_as_played(true, DOWNLOAD_EPISODE.id)
    EpisodeMenu.new(
      app:      app,
      episode:  Dbqueries.episode_from_id(DOWNLOAD_EPISODE.id),
      show_id:  SHOW.id,
      queue_view: false,
    ).build.then do |menu|
      d.check("go-to-show is enabled") { menu.group.lookup_action("go-to-show").enabled? }
      d.check("copy-episode-url is enabled") { menu.group.lookup_action("copy-episode-url").enabled? }
      d.check("mark-as-unplayed is enabled, the episode is played") do
        menu.group.lookup_action("mark-as-unplayed").enabled?
      end
      d.check("mark-as-played is disabled, already played") do
        !menu.group.lookup_action("mark-as-played").enabled?
      end

      menu.group.activate_action("copy-episode-url", nil)
      menu.group.activate_action("mark-as-unplayed", nil)
    end
    d.check("the episode is unplayed again") { !Dbqueries.episode_from_id(DOWNLOAD_EPISODE.id).played? }
  end

  d.step("and the clipboard really holds the episode's url") do
    Gdk::Display.default.clipboard.read_text_async(nil) do |clipboard, result|
      @clipboard_text = clipboard.read_text_finish(result)
    end
  end

  d.step("once the async read lands") do
    context = GLib::MainContext.default
    50.times do
      break unless @clipboard_text.nil?

      context.iteration(false)
      sleep(0.01)
    end
    d.check("the clipboard holds the episode's url") do
      @clipboard_text == Dbqueries.episode_from_id(DOWNLOAD_EPISODE.id).uri
    end
  end

  d.step("go-to-show from the episode menu navigates to the show") do
    EpisodeMenu.new(app: app, episode: Dbqueries.episode_from_id(DOWNLOAD_EPISODE.id), show_id: SHOW.id)
      .build.group.activate_action("go-to-show", nil)
    d.check("the show page is up") { app.main_window.show_page.title == SHOW.title }
  end

  d.step("the download action fetches the file for real") do
    EpisodeMenu.new(app: app, episode: Dbqueries.episode_from_id(DOWNLOAD_EPISODE.id), show_id: SHOW.id)
      .build.group.activate_action("download", nil)
  end

  d.step("and it lands on disk") do
    context = GLib::MainContext.default
    100.times do
      break if Dbqueries.episode_from_id(DOWNLOAD_EPISODE.id).downloaded?

      context.iteration(false)
      sleep(0.02)
    end
    d.check("the episode is marked downloaded") { Dbqueries.episode_from_id(DOWNLOAD_EPISODE.id).downloaded? }
    d.check("the file is really there") do
      File.read(Dbqueries.episode_from_id(DOWNLOAD_EPISODE.id).local_uri) == AUDIO_BODY
    end
  end

  d.step("the delete action removes the file but keeps the row") do
    EpisodeMenu.new(app: app, episode: Dbqueries.episode_from_id(DOWNLOAD_EPISODE.id), show_id: SHOW.id)
      .build.group.activate_action("delete", nil)
    d.check("the episode is no longer downloaded") { !Dbqueries.episode_from_id(DOWNLOAD_EPISODE.id).downloaded? }
    d.check("the row survives") { !Dbqueries.episode_from_id(DOWNLOAD_EPISODE.id).nil? }
    SERVER.close
  end

  d.step("the show menu's unsubscribe hides the show at once") do
    app.main_window.instance_variable_set(:@__captured_toasts, [])
    app.main_window.define_singleton_method(:add_toast) do |toast|
      @__captured_toasts << toast
      toast_overlay.add_toast(toast)
    end

    app.go_to_show(SHOW)
    ShowMenu.new(app: app, show: SHOW, widget: app.main_window.show_widget).build
      .group.activate_action("unsubscribe", nil)
    d.check("the show page popped") { app.main_window.navigation_view.visible_page != app.main_window.show_page }
    app.main_window.content.go_to_shows
    d.check("the show is hidden from the shows grid right away") do
      app.main_window.content.shows_view.store.n_items.zero?
    end
  end

  d.step("pressing Undo on that toast keeps the subscription") do
    toast = app.main_window.instance_variable_get(:@__captured_toasts).last
    d.check("the unsubscribe raised a toast") { !toast.nil? }

    toast.signal_emit("button-clicked")
    toast.dismiss
    d.check("the show is still subscribed, Undo was pressed") { !Dbqueries.podcasts.empty? }
  end

  d.step("and unsubscribing again without Undo deletes it for good") do
    app.go_to_show(SHOW)
    ShowMenu.new(app: app, show: SHOW, widget: app.main_window.show_widget).build
      .group.activate_action("unsubscribe", nil)
    app.main_window.instance_variable_get(:@__captured_toasts).last.dismiss
    d.check("the show is gone") { Dbqueries.podcasts.empty? }
  end

  d.step("ReadMoreLabel starts short and expands on its button") do
    ReadMoreLabel.new.then do |label|
      label.build
      label.label = "first line\nsecond line\nthird line\nfourth line\nfifth line"
      d.check("it starts collapsed") { !label.expanded? }
      d.check("the long label starts hidden") { !label.long_label.visible? }
      label.button.signal_emit("clicked")
      d.check("it is expanded now") { label.expanded? }
      d.check("the long label is visible") { label.long_label.visible? }
    end
  end

  d.step("OPML import indexes new sources and schedules their refresh") do
    File.join(ROOT, "import.opml").then do |path|
      File.write(
        path,
        <<~OPML,
          <?xml version="1.0" encoding="UTF-8"?>
          <opml version="2.0">
            <body>
              <outline type="rss" text="Imported Show" xmlUrl="https://example.com/imported.xml"/>
            </body>
          </opml>
        OPML
      )
      Opml.import_from_file(path).then do |sources|
        d.check("one source was imported") { sources.length == 1 }
        d.check("the url matches the file") { sources.first.uri == "https://example.com/imported.xml" }
      end
    end
  end
end
