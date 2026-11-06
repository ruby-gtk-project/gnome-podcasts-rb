# frozen_string_literal: true

require "adwaita"
require_relative "about_dialog"
require_relative "content_stack"
require_relative "discovery_page"
require_relative "discovery_search_results"
require_relative "episode_description"
require_relative "feed_manager"
require_relative "filter_menu"
require_relative "main_menu"
require_relative "opml_dialogs"

# MainWindow is the app's window: the view switcher over the three pages, the
# navigation view the show page is pushed onto, and the window actions the menu
# and the shortcuts drive.
#
# Ported from podcasts-gtk/src/window.rs and
# podcasts-gtk/resources/gtk/window.ui: the toast overlay around a navigation
# view, the content page tagged "content" with its toolbar view and header bar
# (view switcher as the title, hamburger and filter stack at the end), the
# empty page tagged "show" the show widget is set as the child of, the bottom
# switcher bar that appears in the narrow layout, the breakpoint that decides
# what narrow means, the geometry restored from and written back to the
# settings, and the refresh on startup plus the periodic refresh afterwards.
#
# Upstream's actions that need components the port has not reached yet are not
# installed rather than installed as actions that would do nothing: the player
# ones (win.play, win.pause, win.toggle-pause, win.seek-*, win.set-rate,
# win.raise/lower-playback-rate, win.close-bottom-sheet) arrive with
# lib/player.rb, and win.goto-sync-preferences with lib/sync_preferences.rb.
class MainWindow
  TITLE = "Podcasts"
  WIDTH_REQUEST = 360
  HEIGHT_REQUEST = 294
  # The breakpoint upstream calls header_breakpoint.
  NARROW_CONDITION = "max-width: 550sp"
  PROGRESS_INTERVAL = 100
  REFRESH_WATCH_INTERVAL = 250

  def initialize(app:, settings:)
    @app = app
    @settings = settings
    @mobile_layout = false
  end

  attr_reader :app, :settings

  def mobile_layout? = @mobile_layout

  def build
    window.tap do |win|
      win.content = toast_overlay

      toast_overlay.child = layout_box

      layout_box.tap do |box|
        box.append(navigation_view)
        box.append(toolbar_box)

        navigation_view.tap do |view|
          view.add(content_page)
          view.add(show_page)
          view.signal_connect("popped") { on_popped }
        end

        toolbar_box.append(bottom_switcher_bar)
      end

      content_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = content.build

        header_bar.tap do |header|
          header.title_widget = top_switcher
          header.pack_start(add_feed_button)
          header.pack_end(hamburger)
          header.pack_end(filter_stack)

          top_switcher.stack = content.stack
          bottom_switcher.stack = content.stack
          hamburger.menu_model = main_menu.build

          filter_stack.tap do |stack|
            stack.add_titled(filter_home.build, "home", "Home")
            stack.add_titled(filter_shows.build, "shows", "Shows")
          end
        end
      end

      win.add_breakpoint(narrow_breakpoint)
      narrow_breakpoint.signal_connect("apply") { self.mobile_layout = true }
      narrow_breakpoint.signal_connect("unapply") { self.mobile_layout = false }

      install_actions
      settings.apply_to(win)

      win.signal_connect("close-request") do
        settings.remember(win)
        false
      end

      start_refreshing
    end
  end

  # Upstream's push_page: whatever is pushed stops the bottom switcher being
  # shown, because it is no longer the root page.
  def push_page(page)
    navigation_view.push(page)
    @root_page = false
    update_bottom_switcher_visible
  end

  def pop_to_content
    navigation_view.pop_to_tag("content")
    @root_page = true
    update_bottom_switcher_visible
  end

  def add_toast(toast)
    toast_overlay.add_toast(toast)
  end

  # Upstream's replace_show_widget: the show page's child is swapped, and
  # popped when there is no show to show.
  def replace_show_widget(widget, title)
    @show_widget = widget
    if widget
      show_page.child = widget.build
      show_page.title = title
      widget.mobile_layout = mobile_layout?
      window.insert_action_group("show", widget.action_group)
    else
      show_page.child = nil
      pop_show_widget
    end
  end

  def show_widget = @show_widget

  # Upstream's go_to_discovery: a fresh page each time, as upstream builds
  # one per visit.
  def go_to_discovery
    push_page(DiscoveryPage.new(app: app).build)
  end

  # Upstream's Action::GoToFoundPodcasts.
  def go_to_found_podcasts(results)
    push_page(DiscoverySearchResults.new(app: app, results: results).build)
  end

  # Upstream's episode row activation: a fresh page each visit, tracked so a
  # RefreshEpisode for the episode it shows reaches it too.
  def go_to_episode_description(episode, show)
    @episode_description_widget = EpisodeDescription.new(app: app, episode: episode, show: show)
    push_page(@episode_description_widget.build)
  end

  def episode_description_widget = @episode_description_widget

  # Upstream's go_to_show_widget.
  def go_to_show_widget
    unless navigation_view.visible_page == show_page
      navigation_view.pop_to_tag("content")
      push_page(show_page)
    end
  end

  def pop_show_widget
    if navigation_view.visible_page == show_page
      navigation_view.pop
    end
  end

  # Upstream's open_search: the show page's search when it is up, the content
  # stack's otherwise.
  def open_search
    if navigation_view.visible_page == show_page && show_widget
      show_widget.open_search
    else
      content.open_search
    end
  end

  def mobile_layout=(value)
    @mobile_layout = value
    update_bottom_switcher_visible
    if show_widget
      show_widget.mobile_layout = value
    end
    value
  end

  # Upstream's progress_bar, pulsed while the feeds are being fetched.
  def progress_bar = content.progress_bar

  # Starts the main loop's watch over a refresh that is running, which is how
  # upstream's FetchStarted / FetchDone reach the UI.
  def watch_refresh
    unless @watching_refresh
      @watching_refresh = true
      start_updating
      GLib::Timeout.add(REFRESH_WATCH_INTERVAL) { watch_tick }
    end
  end

  def window
    @window ||= Adwaita::ApplicationWindow.new(app.app).tap do |win|
      win.title = TITLE
      win.set_size_request(WIDTH_REQUEST, HEIGHT_REQUEST)
    end
  end

  def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new
  def layout_box = @layout_box ||= Gtk::Box.new(:vertical, 0)
  def navigation_view
    @navigation_view ||= Adwaita::NavigationView.new.tap do |view|
      view.vexpand = true
    end
  end
  def content_view = @content_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new
  def filter_stack = @filter_stack ||= Adwaita::ViewStack.new
  def filter_home = @filter_home ||= FilterMenu.new(mode: :episode)
  def filter_shows = @filter_shows ||= FilterMenu.new(mode: :show)
  def main_menu = @main_menu ||= MainMenu.new
  def opml_dialogs = @opml_dialogs ||= OpmlDialogs.new(app: app, window: window)

  def content
    @content ||= ContentStack.new(
      app:          app,
      filter_home:  filter_home,
      filter_shows: filter_shows,
      filter_stack: filter_stack,
    )
  end

  # The content page is the navigation view's root, and the one the bottom
  # switcher belongs to.
  def content_page
    @content_page ||= Adwaita::NavigationPage.new(content_view, TITLE).tap do |page|
      page.tag = "content"
    end
  end

  # Translators: Show as a noun, meaning a Podcast-Show.
  def show_page
    @show_page ||= Adwaita::NavigationPage.new(Adwaita::Bin.new, "Show").tap do |page|
      page.tag = "show"
    end
  end

  def top_switcher
    @top_switcher ||= Adwaita::ViewSwitcher.new.tap do |switcher|
      switcher.policy = :wide
    end
  end

  def bottom_switcher = @bottom_switcher ||= Adwaita::ViewSwitcher.new

  def toolbar_box
    @toolbar_box ||= Gtk::Box.new(:vertical, 0)
  end

  def bottom_switcher_bar
    @bottom_switcher_bar ||= Gtk::CenterBox.new.tap do |center|
      center.visible = false
      center.center_widget = bottom_switcher
      center.add_css_class("toolbar")
    end
  end

  def add_feed_button
    @add_feed_button ||= Gtk::Button.new.tap do |button|
      button.tooltip_text = "Add a New Feed"
      button.icon_name = "list-add-symbolic"
      button.action_name = "win.go-to-discovery"
    end
  end

  def hamburger
    @hamburger ||= Gtk::MenuButton.new.tap do |button|
      button.icon_name = "open-menu-symbolic"
      button.tooltip_text = "Main Menu"
      button.primary = true
    end
  end

  def narrow_breakpoint
    @narrow_breakpoint ||= Adwaita::Breakpoint.new(
      Adwaita::BreakpointCondition.parse(NARROW_CONDITION),
    )
  end

  # The window actions, with the accelerators the application binds to them.
  def actions
    {
      "refresh"         => -> { app.refresh_feeds },
      "import"          => -> { opml_dialogs.import },
      "export"          => -> { opml_dialogs.export },
      "about"           => -> { AboutDialog.new(window).present },
      "go-to-home"      => -> { go_to_page { content.go_to_home } },
      "go-to-shows"     => -> { go_to_page { content.go_to_shows } },
      "go-to-queue"     => -> { go_to_page { content.go_to_queue } },
      "go-to-discovery" => -> { go_to_discovery },
      "open-search"     => -> { open_search },
    }
  end

  private

    def install_actions
      actions.each do |name, handler|
        Gio::SimpleAction.new(name).tap do |action|
          action.signal_connect("activate") { handler.call }
          window.add_action(action)
        end
      end
    end

    def go_to_page(&block)
      pop_to_content
      block.call
    end

    def root_page? = @root_page.nil? || @root_page

    # Upstream's update_bottom_switcher_visible: the bar is only up in the
    # narrow layout, and only on the root page.
    def update_bottom_switcher_visible
      bottom_switcher_bar.visible = root_page? && mobile_layout?
    end

    def on_popped
      navigation_view.visible_page.then do |page|
        if page == content_page
          @root_page = true
          update_bottom_switcher_visible
        end
      end
    end

    # Upstream's "refresh on startup" setting, and the periodic refresh after
    # it.
    def start_refreshing
      if settings["refresh-on-startup"]
        app.refresh_feeds
      end

      if settings["refresh-interval"]
        GLib::Timeout.add_seconds(settings.refresh_interval_seconds) do
          app.refresh_feeds
          true
        end
      end
    end

    # Upstream's StartUpdating: the progress bar appears and pulses.
    def start_updating
      progress_bar.visible = true
      GLib::Timeout.add(PROGRESS_INTERVAL) do
        progress_bar.pulse
        @watching_refresh
      end
    end

    # One turn of the watch over a running refresh: collect what finished,
    # and when nothing is running any more, refresh the views.
    def watch_tick
      FeedManager.drain_finished.each { |result| report(result) }
      if FeedManager.running?
        true
      else
        stop_updating
        false
      end
    end

    def stop_updating
      @watching_refresh = false
      progress_bar.visible = false
      content.update
    end

    def report(result)
      if result.error
        app.error_notification("#{result.source.uri}: #{result.error.message}")
      end
    end
end
