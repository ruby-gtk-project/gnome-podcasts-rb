# frozen_string_literal: true

require "adwaita"
require_relative "base_view"
require_relative "dbqueries"
require_relative "download_covers"
require_relative "empty_show"
require_relative "episode_widget"
require_relative "filter_menu"
require_relative "read_more_label"
require_relative "show_menu"
require_relative "xml_parser"

# ShowWidget is the page one show gets: its cover, its description, and its
# episodes.
#
# Ported from podcasts-gtk/src/widgets/show.rs and
# podcasts-gtk/resources/gtk/show_widget.ui: a toolbar view with the show menu
# and a filter menu in the header bar, a search bar under it, then the
# scrolling base view holding a 256px cover, the description in a
# ReadMoreLabel clamped to 600px (320px in the narrow layout) and the episode
# list in a content-styled ListBox. An empty feed shows EmptyShow, and a
# filter that matches nothing shows the same widget with its filter wording.
class ShowWidget
  COVER_SIZE = 256
  DESCRIPTION_WIDTH = 600
  NARROW_DESCRIPTION_WIDTH = 320
  SEARCH_WIDTH = 300

  def initialize(app:, show:)
    @app = app
    @show = show
    @rows = {}
  end

  attr_reader :app, :show

  def show_id = show.id

  def build
    page_view.tap do |view|
      view.add_top_bar(header_bar)
      view.add_top_bar(search_bar)
      view.content = base_view.build

      header_bar.tap do |header|
        header.pack_end(secondary_menu)
        header.pack_end(filter_menu.build)

        secondary_menu.menu_model = show_menu.build.menu
      end

      search_bar.tap do |bar|
        bar.child = search_entry
        bar.key_capture_widget = base_view.bin

        search_entry.signal_connect("search-changed") { reload }
      end

      base_view.content = clamp

      clamp.tap do |clamped|
        clamped.child = sub_container

        sub_container.tap do |box|
          box.append(cover)
          DownloadCovers.load_widget_texture(
            cover,
            show.id,
            COVER_SIZE,
            set_tooltip: true,
          )
          box.append(description_clamp)
          box.append(episodes_container)

          description_clamp.child = read_more_label.init.build
          read_more_label.label = description_text
        end
      end

      filter_menu.on_filter_changed { reload }
      filter_menu.search_button.bind_property(
        "active",
        search_bar,
        "search-mode-enabled",
        [:sync_create, :bidirectional],
      )

      populate_listbox
    end
  end

  # The action group the window has to carry for the menu to work, and the
  # name upstream inserts it under.
  def action_group = show_menu.group

  # Upstream's reload: re-read the show and rebuild the list for the current
  # filter.
  def reload
    @show = Dbqueries.podcast_from_id(show_id)
    populate_listbox
  end

  # Upstream's open_search.
  def open_search
    search_bar.search_mode = true
  end

  def update_episode(episode)
    @rows[episode.id].then do |widget|
      if widget
        widget.update_episode_state(episode)
      end
    end
  end

  # Upstream's mark_all_played: every row on the page goes dim at once, before
  # anything is written.
  def mark_all_played
    @rows.each_value { |widget| widget.played = true }
  end

  # Upstream's episode_filter.
  def episode_filter
    filter_menu.episode_filter.tap do |filter|
      unless search_entry.text.to_s.empty?
        filter.search = search_entry.text
      end
    end
  end

  # Upstream binds the description's clamp to the window's narrow layout.
  def mobile_layout=(value)
    if value
      description_clamp.maximum_size = NARROW_DESCRIPTION_WIDTH
    else
      description_clamp.maximum_size = DESCRIPTION_WIDTH
    end
    value
  end

  def page_view = @page_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new
  def base_view = @base_view ||= BaseView.new
  def search_bar = @search_bar ||= Gtk::SearchBar.new
  def read_more_label = @read_more_label ||= ReadMoreLabel.new
  def filter_menu = @filter_menu ||= FilterMenu.new(mode: :episode)
  def show_menu = @show_menu ||= ShowMenu.new(app: app, show: show, widget: self)
  def episodes_container = @episodes_container ||= Adwaita::Bin.new
  def clamp = @clamp ||= Adwaita::Clamp.new

  def secondary_menu
    @secondary_menu ||= Gtk::MenuButton.new.tap do |menu_button|
      menu_button.icon_name = "view-more-symbolic"
      menu_button.tooltip_text = "Podcast Menu"
      menu_button.primary = true
    end
  end

  def search_entry
    @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
      entry.set_size_request(SEARCH_WIDTH, -1)
    end
  end

  def sub_container
    @sub_container ||= Gtk::Box.new(:vertical, 6).tap do |box|
      box.margin_top = 32
      box.margin_bottom = 32
      box.hexpand = true
    end
  end

  # Upstream's set_cover: the 256px thumbnail, with the show's title as the
  # tooltip, over the fallback the page shows while it is being fetched.
  def cover
    @cover ||= Gtk::Image.new(icon_name: "image-missing-symbolic").tap do |image|
      image.pixel_size = COVER_SIZE
      image.halign = :center
      image.focusable = true
      image.add_css_class("rounded-big")
    end
  end

  def description_clamp
    @description_clamp ||= Adwaita::Clamp.new.tap do |clamped|
      clamped.maximum_size = DESCRIPTION_WIDTH
    end
  end

  def episodes_list
    @episodes_list ||= Gtk::ListBox.new.tap do |list_box|
      list_box.margin_start = 12
      list_box.margin_end = 12
      list_box.margin_top = 12
      list_box.margin_bottom = 12
      list_box.valign = :start
      list_box.selection_mode = :none
      list_box.activate_on_single_click = true
      list_box.add_css_class("content")
    end
  end

  private

    # Upstream runs the feed's html description through html2text before
    # handing it to the label; the port strips the tags and unescapes the
    # entities, which is the same job on the markup feeds actually carry.
    def description_text
      show.description.gsub(%r{<br\s*/?>|</p>}i, "\n")
        .gsub(/<[^>]+>/, "")
        .then { |text| XmlParser.unescape(text) }
        .split("\n")
        .map(&:strip)
        .join("\n")
        .strip
    end

    # Upstream's populate_listbox, plus its two empty states.
    def populate_listbox
      @rows = {}
      if Dbqueries.pd_episodes_count(show).zero?
        make_empty(false)
      else
        fill_listbox(Dbqueries.pd_episode_widgets(show, episode_filter))
      end
    end

    def fill_listbox(episodes)
      if episodes.empty?
        make_empty(true)
      else
        clear_listbox
        episodes_container.child = episodes_list
        episodes.each { |episode| episodes_list.append(row_for(episode)) }
      end
    end

    def row_for(episode)
      EpisodeWidget.new(
        app:           app,
        episode:       episode,
        add_show_link: false,
      ).then do |widget|
        @rows[episode.id] = widget
        widget.build
      end
    end

    def clear_listbox
      while episodes_list.first_child
        episodes_list.remove(episodes_list.first_child)
      end
    end

    def make_empty(due_to_filter)
      EmptyShow.new.then do |empty|
        if due_to_filter
          empty.empty_because_of_filter
        end
        episodes_container.child = Gtk::ListBox.new.tap do |list_box|
          list_box.add_css_class("content")
          list_box.append(empty.build)
        end
      end
    end
end
