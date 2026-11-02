# frozen_string_literal: true

require "adwaita"
require_relative "base_view"
require_relative "dbqueries"
require_relative "download_covers"
require_relative "utils"

# ShowsView is the Shows page: a grid of covers, one per subscription.
#
# Ported from podcasts-gtk/src/widgets/shows_view.rs: a GridView of 150px
# pictures with a SignalListItemFactory, two to seven columns, a horizontal
# clamp at seven columns' worth of width, single-click activation that opens
# the show, a search bar bound to the filter menu's toggle, and a "No Results
# Found" page in place of the grid when the filter matches nothing.
#
# Upstream's model items are a ShowCoverModel GObject carrying the show id and
# the handle of its cover download. Defining a GObject subclass is not worth it
# in these bindings, so the shows live in a Ruby array and the grid's model is a
# NoSelection over a store of StringObjects standing for their positions; the
# factory and the activation handler read the show back out by position.
class ShowsView
  COVER_SIZE = 150
  # Upstream's Thumb256, the thumbnail size the grid's covers come from.
  THUMB_SIZE = 256
  MIN_COLUMNS = 2
  MAX_COLUMNS = 7
  # picture + paddings * max_columns, as upstream computes it
  CLAMP_SIZE = (256 + 6 + 6) * 7
  SEARCH_WIDTH = 300

  def initialize(app:, filter_menu:)
    @app = app
    @filter_menu = filter_menu
    @shows = []
  end

  attr_reader :app, :filter_menu

  def build
    bin.tap do |root|
      root.child = container

      container.tap do |toolbar|
        toolbar.add_top_bar(search_bar)
        toolbar.content = content_box

        search_bar.tap do |bar|
          bar.child = search_entry
          bar.key_capture_widget = base_view.bin

          search_entry.signal_connect("search-changed") { update_model }
        end

        content_box.tap do |box|
          box.append(empty_filter_page)
          box.append(base_view.build)
        end

        base_view.content = clamp

        clamp.tap do |clamped|
          clamped.child = grid

          grid.tap do |grid_view|
            grid_view.factory = factory
            grid_view.signal_connect("activate") { |_, position| activate(position) }
          end
        end
      end

      filter_menu.on_filter_changed { update_model }
      filter_menu.search_button.bind_property(
        "active",
        search_bar,
        "search-mode-enabled",
        [:sync_create, :bidirectional],
      )

      update_model
    end
  end

  # Upstream's update_model / set_data.
  def update_model
    Dbqueries.podcasts_filter(Utils.ignored_shows, show_filter).then do |shows|
      @shows = shows
      empty_filter_page.visible = shows.empty?
      base_view.bin.visible = !shows.empty?
      refill(shows)
    end
  end

  # Upstream's open_search.
  def open_search
    search_bar.search_mode = true
  end

  # Upstream's show_filter: the menu's filter with the search text folded in.
  def show_filter
    filter_menu.show_filter.then do |filter|
      Dbqueries::ShowFilter.new(
        any_downloaded:       filter.any_downloaded,
        completed:            filter.completed,
        title_or_description: search_text,
        reverse_order:        filter.reverse_order,
      )
    end
  end

  def bin = @bin ||= Adwaita::Bin.new
  def container = @container ||= Adwaita::ToolbarView.new
  def base_view = @base_view ||= BaseView.new
  def search_bar = @search_bar ||= Gtk::SearchBar.new
  def store = @store ||= Gio::ListStore.new(Gtk::StringObject)

  def content_box
    @content_box ||= Gtk::Box.new(:vertical, 5).tap do |box|
      box.vexpand = true
    end
  end

  def search_entry
    @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
      entry.set_size_request(SEARCH_WIDTH, -1)
    end
  end

  def empty_filter_page
    @empty_filter_page ||= Adwaita::StatusPage.new.tap do |page|
      page.title = "No Results Found"
      page.description = "Try a different search or filters"
      page.icon_name = "system-search-symbolic"
      page.valign = :center
      page.vexpand = true
      page.visible = false
    end
  end

  def clamp
    @clamp ||= Adwaita::ClampScrollable.new.tap do |clamped|
      clamped.valign = :fill
      clamped.halign = :fill
      clamped.orientation = :horizontal
      clamped.maximum_size = CLAMP_SIZE
    end
  end

  def grid
    @grid ||= Gtk::GridView.new.tap do |grid_view|
      grid_view.model = Gtk::NoSelection.new(store)
      grid_view.single_click_activate = true
      grid_view.can_focus = true
      grid_view.vexpand = true
      grid_view.hexpand = true
      grid_view.min_columns = MIN_COLUMNS
      grid_view.max_columns = MAX_COLUMNS
      grid_view.valign = :fill
      grid_view.halign = :fill
      grid_view.set_size_request(-1, 500)
      grid_view.tab_behavior = :item
      grid_view.add_css_class("shows-grid")
    end
  end

  # The factory builds one picture per item, labels it with the show's title
  # and asks lib/download_covers.rb for the 256px thumbnail, which arrives
  # once it has been fetched and generated.
  def factory
    @factory ||= Gtk::SignalListItemFactory.new.tap do |signal_factory|
      signal_factory.signal_connect("setup") { |_, item| item.child = cover_picture }
      signal_factory.signal_connect("bind") { |_, item| bind_cover(item) }
    end
  end

  private

    def search_text
      search_entry.text.to_s.then do |text|
        unless text.empty?
          text
        end
      end
    end

    def cover_picture
      Gtk::Image.new(icon_name: "image-missing-symbolic").tap do |image|
        image.set_size_request(COVER_SIZE, COVER_SIZE)
        image.pixel_size = COVER_SIZE / 2
        image.can_focus = false
        image.add_css_class("flat")
        image.add_css_class("rounded-big")
        image.add_css_class("show-button")
      end
    end

    def bind_cover(item)
      @shows[item.position].then do |show|
        if show
          DownloadCovers.load_widget_texture(
            item.child,
            show.id,
            THUMB_SIZE,
            set_tooltip: true,
          )
        end
      end
    end

    def refill(shows)
      store.remove_all
      shows.each_with_index do |_show, index|
        store.append(Gtk::StringObject.new(index.to_s))
      end
    end

    # Upstream's on_child_activate: open the show the cell stands for.
    def activate(position)
      @shows[position].then do |show|
        if show
          app.go_to_show(show)
        end
      end
    end
end
