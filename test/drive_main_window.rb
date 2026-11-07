# frozen_string_literal: true

# Drives the app: seeds the row store from a feed fixture, then walks the
# window the way a user would — the three pages, a show page, the filters, the
# queue — checking what each step left behind and taking a screenshot of it.
#
# Run it from the dev shell:
#   xvfb-run ruby test/drive_main_window.rb
#
# It writes PNGs under tmp/shots and exits non-zero if any check fails.

require "tmpdir"
require "fileutils"

# A scratch XDG tree, so a test run never reads or writes the real library.
ROOT = Dir.mktmpdir("gnome-podcasts-drive")
ENV["XDG_DATA_HOME"] = File.join(ROOT, "data")
ENV["XDG_CONFIG_HOME"] = File.join(ROOT, "config")
ENV["XDG_CACHE_HOME"] = File.join(ROOT, "cache")

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "gnome_podcasts"
require "feed"
require "opml"
require "xml_parser"

require_relative "gtk_driver"

FIXTURE = File.expand_path("feeds/intercepted.xml", __dir__)

# Index the fixture feed, the way a refresh would.
SOURCE = Source.from_url("https://example.com/intercepted.xml")
SHOW = Feed.new(
  channel:   XmlParser.parse(File.read(FIXTURE)),
  source_id: SOURCE.id,
).index
EPISODES = Dbqueries.episodes_of(SHOW.id).sort_by { |episode| -episode.epoch.to_i }

# No refresh on startup: the fixture's urls do not resolve, and the run should
# not wait on DNS to find that out.
SETTINGS = Settings.new(path: File.join(ROOT, "settings.json"))
SETTINGS["refresh-on-startup"] = false
SETTINGS["refresh-interval"] = false

APP = GnomePodcasts::Application.new(settings: SETTINGS)

GtkDriver.drive(APP, shots: "tmp/shots") do |d, app|
  d.window { app.window }

  d.step("the window opens on the Home page") do
    d.check("the fixture indexed 43 episodes") { EPISODES.length == 43 }
    d.check("the window is mapped") { app.window.mapped? }
    d.check("the window has a size") do
      # The first size-allocate under Xvfb sometimes lands a beat after this
      # step's own tick, especially under host load — pump the main context a
      # little further rather than widen the whole driver's interval or weaken
      # this into a non-check.
      context = GLib::MainContext.default
      50.times do
        break if app.window.width.positive? && app.window.height.positive?

        context.iteration(false)
        sleep(0.01)
      end
      app.window.width.positive? && app.window.height.positive?
    end
    d.check("home is the visible page") { app.main_window.content.stack.visible_child_name == "home" }
    d.check("the first episode has a row") do
      !app.main_window.content.home_view.episode_list.episode_widget(EPISODES.first.id).nil?
    end
    d.shot("01-home")
  end

  d.step("the Shows page lists the subscription") do
    app.main_window.content.go_to_shows
    d.check("the grid has one item") { app.main_window.content.shows_view.store.n_items == 1 }
    d.shot("02-shows")
  end

  d.step("the Queue page starts empty") do
    app.main_window.content.go_to_queue
    d.check("the empty page is up") { app.main_window.content.queue_view.empty_status_page.visible? }
    d.shot("03-queue-empty")
  end

  d.step("an episode can be queued") do
    app.add_to_queue(EPISODES.first.id)
    d.check("the queue has one row") { Dbqueries.queue.length == 1 }
    d.check("the row is on the page") do
      !app.main_window.content.queue_view.episode_widget(EPISODES.first.id).nil?
    end
    d.check("the empty page is down") { !app.main_window.content.queue_view.empty_status_page.visible? }
    d.shot("04-queue-filled")
  end

  d.step("a second episode is queued, then moved up through its row menu") do
    app.add_to_queue(EPISODES[1].id)
    d.check("the queue has two rows") { Dbqueries.queue.length == 2 }
    d.check("the new episode sorted to the bottom") { !Dbqueries.first_position_in_queue?(EPISODES[1].id) }

    EpisodeMenu.new(app: app, episode: Dbqueries.episode_from_id(EPISODES[1].id), queue_view: true)
      .build.group.activate_action("move-up-in-queue", nil)
    d.check("the move-up action put it first") { Dbqueries.first_position_in_queue?(EPISODES[1].id) }
  end

  d.step("and moved back down, then removed, through the same menu") do
    EpisodeMenu.new(app: app, episode: Dbqueries.episode_from_id(EPISODES[1].id), queue_view: true)
      .build.group.activate_action("move-down-in-queue", nil)
    d.check("the move-down action put it last again") { !Dbqueries.first_position_in_queue?(EPISODES[1].id) }

    app.remove_from_queue(EPISODES[1].id)
    d.check("the queue is back to one row") { Dbqueries.queue.length == 1 }
    d.check("the removed row left the page") do
      app.main_window.content.queue_view.episode_widget(EPISODES[1].id).nil?
    end
  end

  d.step("the show page opens") do
    app.go_to_show(SHOW)
    d.check("the page is titled after the show") { app.main_window.show_page.title == SHOW.title }
    d.check("the show page is the visible one") do
      app.main_window.navigation_view.visible_page == app.main_window.show_page
    end
    d.check("the description made it into the label") do
      !app.main_window.show_widget.read_more_label.long_label.label.empty?
    end
    d.check("the episode list has rows") do
      !app.main_window.show_widget.episodes_list.first_child.nil?
    end
    d.shot("05-show")
  end

  d.step("marking an episode played dims its row") do
    app.mark_as_played(true, EPISODES.first.id)
    d.check("the row is marked played") do
      app.main_window.show_widget.instance_variable_get(:@rows)[EPISODES.first.id]
        .played_checkmark.visible?
    end
    d.check("the row is played in the database") { Dbqueries.episode_from_id(EPISODES.first.id).played? }
    d.shot("06-played")
  end

  d.step("the filter menu narrows the show's episodes to played ones") do
    app.main_window.show_widget.filter_menu
      .action("played")
      .change_state(GLib::Variant.new("yes"))
    d.check("the filter reports played-only") do
      app.main_window.show_widget.episode_filter.played == true
    end
    d.check("one row is left") do
      app.main_window.show_widget.instance_variable_get(:@rows).length == 1
    end
    d.shot("07-filtered")
  end

  d.step("the show menu's mark-all-played toast defers the write until it closes") do
    app.main_window.instance_variable_set(:@__captured_toasts, [])
    app.main_window.define_singleton_method(:add_toast) do |toast|
      @__captured_toasts << toast
      toast_overlay.add_toast(toast)
    end

    d.check("the target episode starts unplayed") { !Dbqueries.episode_from_id(EPISODES[2].id).played? }

    ShowMenu.new(app: app, show: SHOW, widget: app.main_window.show_widget).build
      .group.activate_action("mark-played", nil)

    toast = app.main_window.instance_variable_get(:@__captured_toasts).last
    d.check("the menu action raised a toast") { !toast.nil? }
    d.check("the database write waits for the toast to close") do
      !Dbqueries.episode_from_id(EPISODES[2].id).played?
    end

    toast.dismiss
    d.check("dismissing without Undo commits the mark") { Dbqueries.episode_from_id(EPISODES[2].id).played? }
  end

  d.step("the search bar opens on the show page") do
    app.main_window.open_search
    d.check("search mode is on") { app.main_window.show_widget.search_bar.search_mode? }
    d.shot("08-search")
  end

  d.step("the empty state replaces the pages when nothing is subscribed") do
    app.main_window.pop_to_content
    app.empty_state
    d.check("the empty page is visible") { app.main_window.content.stack.visible_child_name == "empty" }
    d.check("the switcher went insensitive") { !app.main_window.top_switcher.sensitive? }
  end

  # The navigation animation is still running when the step above ends, so the
  # empty page is photographed a tick later, once it has settled.
  d.step("and the empty page settles") do
    d.shot("09-empty")
  end

  d.step("and goes away again once there is something to show") do
    app.populated_state
    d.check("home is back") { app.main_window.content.stack.visible_child_name == "home" }
    d.check("the switcher is sensitive again") { app.main_window.top_switcher.sensitive? }
    d.shot("10-populated")
  end

  d.step("the shortcuts dialog and the about dialog build") do
    d.check("the shortcuts dialog builds") { !app.shortcuts_dialog.build.nil? }
    d.check("the about dialog knows the version") do
      AboutDialog.new(app.window).dialog.version == Gnome::Podcasts::Rb::VERSION
    end
  end

  d.step("OPML round-trips through the file") do
    File.join(ROOT, "export.opml").then do |path|
      Opml.export_from_db(path, "GNOME Podcasts Subscriptions")
      d.check("the export names the feed") { File.read(path).include?(SOURCE.uri) }
      d.check("the export parses back to one outline") { Opml.extract_sources(File.read(path)).length == 1 }
    end
  end
end
