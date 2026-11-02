# frozen_string_literal: true

require "adwaita"
require_relative "base_view"
require_relative "home_episode_list"

# HomeView is the "New" page: every show's episodes in one list, newest first.
#
# Ported from podcasts-gtk/src/widgets/home_view.rs and
# podcasts-gtk/resources/gtk/home_view.ui: a toolbar view with a search bar on
# top, the scrolling base view under it, a 700px clamp around the episode list,
# the search entry's 500ms delay, the filter menu's search toggle bound to the
# search bar, and a reload whenever either the search text or the filter
# changes.
class HomeView
  CLAMP_SIZE = 700
  SEARCH_DELAY = 500
  SEARCH_WIDTH = 300

  def initialize(app:, filter_menu:)
    @app = app
    @filter_menu = filter_menu
  end

  attr_reader :app, :filter_menu

  def build
    bin.tap do |root|
      root.child = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(search_bar)
        view.content = base_view.build

        search_bar.tap do |bar|
          bar.child = search_entry
          bar.key_capture_widget = base_view.bin

          search_entry.signal_connect("search-changed") { reload }
        end

        base_view.content = clamp

        clamp.tap do |clamped|
          clamped.child = episode_list.build
        end
      end

      filter_menu.on_filter_changed { reload }
      filter_menu.search_button.bind_property(
        "active",
        search_bar,
        "search-mode-enabled",
        [:sync_create, :bidirectional],
      )

      reload
    end
  end

  # Upstream's reload: a fresh list for the current filter and search text.
  def reload
    episode_list.load(episode_filter)
  end

  # Upstream's open_search.
  def open_search
    search_bar.search_mode = true
  end

  def update_episode(episode)
    episode_list.update_episode(episode)
  end

  # Upstream's episode_filter: the menu's filter, with the search entry's text
  # folded in.
  def episode_filter
    filter_menu.episode_filter.tap do |filter|
      unless search_entry.text.to_s.empty?
        filter.search = search_entry.text
      end
    end
  end

  def bin = @bin ||= Adwaita::Bin.new
  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def base_view = @base_view ||= BaseView.new
  def episode_list = @episode_list ||= HomeEpisodeList.new(app: app)
  def search_bar = @search_bar ||= Gtk::SearchBar.new

  def search_entry
    @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
      entry.set_size_request(SEARCH_WIDTH, -1)
      entry.search_delay = SEARCH_DELAY
    end
  end

  def clamp
    @clamp ||= Adwaita::Clamp.new.tap do |clamped|
      clamped.maximum_size = CLAMP_SIZE
    end
  end
end
