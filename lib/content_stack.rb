# frozen_string_literal: true

require "adwaita"
require_relative "dbqueries"
require_relative "empty_view"
require_relative "home_view"
require_relative "queue_view"
require_relative "shows_view"
require_relative "utils"

# ContentStack is the three pages the view switcher switches between, and the
# empty state that replaces all three.
#
# Ported from podcasts-gtk/src/widgets/content_stack.rs: a ViewStack of New,
# Shows and Queue with their icons, a fourth unnamed page for the empty state,
# an overlay carrying the "Fetching feeds…" progress bar over the lot, the
# lazy initialization of the Shows and Queue pages on first visit, and the
# filter menu stack that follows the visible page.
class ContentStack
  PAGES = [
    ["home", "New", "document-open-recent-symbolic"],
    ["shows", "Shows", "audio-input-microphone-symbolic"],
    ["queue", "Queue", "view-list-symbolic"],
  ].freeze

  def initialize(app:, filter_home:, filter_shows:, filter_stack:)
    @app = app
    @filter_home = filter_home
    @filter_shows = filter_shows
    @filter_stack = filter_stack
  end

  attr_reader :app, :filter_home, :filter_shows, :filter_stack

  def build
    overlay.tap do |root|
      root.child = stack
      root.add_overlay(progress_bar)

      stack.tap do |view_stack|
        add_page(home_view.build, "home")
        add_page(shows_bin, "shows")
        add_page(queue_bin, "queue")
        view_stack.add_named(empty_view.build, "empty")

        view_stack.signal_connect("notify::visible-child") { on_visible_child_changed }
      end
    end
  end

  # Upstream's update: every page reloaded, then the empty check.
  def update
    update_home
    update_queue
    update_shows
    check_empty_state
  end

  def update_home
    home_view.reload
  end

  def update_shows
    if @shows_view
      shows_view.update_model
    end
  end

  def update_queue
    if @queue_view
      queue_view.reload
    end
  end

  def update_home_episode(episode)
    home_view.update_episode(episode)
  end

  def update_queue_episode(episode)
    if @queue_view
      queue_view.update_episode(episode)
    end
  end

  # Upstream's update_queue_after_removal / update_queue_after_move: the page
  # patches itself where it can and reloads where it cannot.
  def update_queue_after_removal(episode_id)
    unless @queue_view && queue_view.update_after_removal(episode_id)
      update_queue
    end
  end

  def update_queue_after_move(episode_id, new_index)
    unless @queue_view && queue_view.update_after_move(episode_id, new_index)
      update_queue
    end
  end

  # Upstream's check_empty_state: the empty page stands in for everything
  # while no show has an episode.
  def check_empty_state
    if Dbqueries.episodes_populated?(Utils.ignored_shows)
      app.populated_state
    else
      app.empty_state
    end
  end

  def go_to_home
    unless empty_view?
      stack.visible_child_name = "home"
    end
  end

  def go_to_shows
    unless empty_view?
      stack.visible_child_name = "shows"
    end
  end

  def go_to_queue
    unless empty_view?
      stack.visible_child_name = "queue"
    end
  end

  def switch_to_empty_views
    stack.visible_child_name = "empty"
  end

  def switch_to_populated
    stack.visible_child_name = "home"
  end

  def empty_view? = stack.visible_child_name == "empty"

  # Upstream's open_search, which goes to whichever page is showing.
  def open_search
    if stack.visible_child_name == "shows"
      shows_view.open_search
    elsif stack.visible_child_name == "home"
      home_view.open_search
    end
  end

  def overlay = @overlay ||= Gtk::Overlay.new
  def stack = @stack ||= Adwaita::ViewStack.new
  def shows_bin = @shows_bin ||= Adwaita::Bin.new
  def queue_bin = @queue_bin ||= Adwaita::Bin.new
  def empty_view = @empty_view ||= EmptyView.new
  def home_view = @home_view ||= HomeView.new(app: app, filter_menu: filter_home)

  # Upstream builds these two the first time their page is visited, so the
  # start-up does not pay for pages nobody opened.
  def shows_view
    @shows_view ||= ShowsView.new(app: app, filter_menu: filter_shows).tap do |view|
      shows_bin.child = view.build
    end
  end

  def queue_view
    @queue_view ||= QueueView.new(app: app).tap do |view|
      queue_bin.child = view.build
    end
  end

  def progress_bar
    @progress_bar ||= Gtk::ProgressBar.new.tap do |bar|
      bar.valign = :start
      bar.halign = :fill
      bar.visible = false
      bar.tooltip_text = "Fetching feeds…"
      bar.add_css_class("osd")
    end
  end

  private

    def add_page(widget, name)
      PAGES.find { |page_name, _, _| page_name == name }.then do |_, title, icon|
        stack.add_titled(widget, name, title).tap do |page|
          page.icon_name = icon
        end
      end
    end

    # Upstream's two visible-child handlers: build the page being switched to,
    # and point the header's filter stack at the matching filter menu.
    def on_visible_child_changed
      stack.visible_child_name.then do |name|
        if name == "shows"
          filter_stack.visible_child_name = "shows"
          shows_view
        end
        if name == "queue"
          queue_view
        end
        if name == "home"
          filter_stack.visible_child_name = "home"
        end
      end
    end
end
