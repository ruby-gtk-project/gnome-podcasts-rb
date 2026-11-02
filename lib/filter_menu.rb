# frozen_string_literal: true

require "adwaita"
require_relative "dbqueries"

# FilterMenu is the funnel button in the header bar, and the search toggle
# next to it.
#
# Ported from podcasts-gtk/src/widgets/filter_menu.rs and
# podcasts-gtk/resources/gtk/filter_menu.ui: three stateful actions — order,
# played and downloaded — in a "filter" action group, two menu models (one
# worded for episodes, one for shows), a dot over the button while any filter
# is set, and a toggle the pages bind their search bar to.
#
# Upstream emits a "filter-changed" GObject signal; a custom signal means
# subclassing GLib::Object in these bindings, so the port keeps a list of
# callbacks and `on_filter_changed` registers one.
class FilterMenu
  EPISODE_MENU = [
    [
      # Translators: (in a filter menu) sort "Newest" episodes on top of the list
      ["Newest First", "filter.order", "default"],
      # Translators: (in a filter menu) sort "Oldest" episodes on top of the list
      ["Oldest First", "filter.order", "reversed"],
    ],
    [
      # Translators: (in a filter menu) list "All" episodes regardless of play status
      ["All", "filter.played", "all"],
      # Translators: (in a filter menu) list only "Played" episodes
      ["Played", "filter.played", "yes"],
      # Translators: (in a filter menu) list only "Not Played" episodes
      ["Not Played", "filter.played", "no"],
    ],
    [
      # Translators: (in a filter menu) list "All" episodes regardless of download status
      ["All", "filter.downloaded", "all"],
      # Translators: (in a filter menu) list only "Downloaded" episodes
      ["Downloaded", "filter.downloaded", "yes"],
      # Translators: (in a filter menu) list only "Not Downloaded" episodes
      ["Not Downloaded", "filter.downloaded", "no"],
    ],
  ].freeze

  SHOW_MENU = [
    [
      # Translators: (in a filter menu) Sorting Shows in alphabetical
      ["Alphabetical", "filter.order", "default"],
      # Translators: (in a filter menu) Sorting Shows in reverse alphabetical
      ["Reversed", "filter.order", "reversed"],
    ],
    [
      # Translators: (in a filter menu) list "All" Shows regardless of completion status
      ["All", "filter.played", "all"],
      # Translators: (in a filter menu) filter for Shows where all episodes were played
      ["Completed", "filter.played", "yes"],
      # Translators: (in a filter menu) filter for Shows with unplayed episodes
      ["Not Completed", "filter.played", "no"],
    ],
    [
      # Translators: (in a filter menu) list "All" Shows regardless if they have downloaded episodes
      ["All", "filter.downloaded", "all"],
      # Translators: (in a filter menu) filter for Shows with "Downloaded" episodes
      ["Downloaded", "filter.downloaded", "yes"],
      # Translators: (in a filter menu) filter for Shows with no "Downloaded" episodes
      ["Not Downloaded", "filter.downloaded", "no"],
    ],
  ].freeze

  STATES = {
    "order"      => "default",
    "played"     => "all",
    "downloaded" => "all",
  }.freeze

  # `mode` is upstream's FilterMenuMode: :episode or :show.
  def initialize(mode: :episode)
    @mode = mode
    @callbacks = []
  end

  attr_reader :mode

  def build
    box.tap do |root|
      root.append(search_button)
      root.append(overlay)

      overlay.tap do |over|
        over.child = button
        over.add_overlay(is_active_circle)

        button.tap do |menu_button|
          menu_button.menu_model = menu_model
        end
      end

      STATES.each_key { |name| group.add_action(action(name)) }
      root.insert_action_group("filter", group)
    end
  end

  def on_filter_changed(&block)
    @callbacks << block
  end

  # Upstream's episode_filter.
  def episode_filter
    Dbqueries::EpisodeFilter.new(
      downloaded:    tristate("downloaded"),
      played:        tristate("played"),
      search:        nil,
      reverse_order: state("order") == "reversed",
    )
  end

  # Upstream's show_filter, which reads the same three actions.
  def show_filter
    Dbqueries::ShowFilter.new(
      any_downloaded:       tristate("downloaded"),
      completed:            tristate("played"),
      title_or_description: nil,
      reverse_order:        state("order") == "reversed",
    )
  end

  # The bindings hand back the state variant already unwrapped, as a String.
  def state(name) = action(name).state.to_s

  def box = @box ||= Gtk::Box.new(:horizontal, 6)
  def overlay = @overlay ||= Gtk::Overlay.new
  def group = @group ||= Gio::SimpleActionGroup.new

  def search_button
    @search_button ||= Gtk::ToggleButton.new.tap do |toggle|
      toggle.icon_name = "system-search-symbolic"
      # Translators: Tooltip text for a button that toggles the search bar
      toggle.tooltip_text = "Toggle Search"
    end
  end

  def button
    @button ||= Gtk::MenuButton.new.tap do |menu_button|
      # The funnel is one of the app's own icons; see lib/icons.rb.
      menu_button.icon_name = "funnel-outline-symbolic"
      # Translators: Tooltip text for a menu button that has filter, sorting, and search options
      menu_button.tooltip_text = "Filter"
    end
  end

  def is_active_circle
    @is_active_circle ||= Gtk::Box.new(:horizontal, 0).tap do |circle|
      circle.halign = :end
      circle.valign = :start
      circle.margin_end = 5
      circle.margin_top = 5
      circle.can_focus = false
      circle.can_target = false
      circle.visible = false
      circle.add_css_class("circle-overlay")
    end
  end

  def menu_model
    @menu_model ||= Gio::Menu.new.tap do |model|
      sections.each { |items| model.append_section(nil, section(items)) }
    end
  end

  # The three stateful actions, memoized one per name.
  def action(name)
    # There is no `new_stateful` in these bindings; a third argument to `new`
    # is what makes the action stateful.
    actions[name] ||= Gio::SimpleAction.new(
      name,
      GLib::VariantType.new("s"),
      GLib::Variant.new(STATES.fetch(name)),
    ).tap do |simple|
      # The value arrives unwrapped, as a String, but the state setter wants
      # a variant back.
      simple.signal_connect("change-state") do |changed, value|
        changed.state = GLib::Variant.new(value.to_s)
        filter_changed
      end
    end
  end

  private

    def actions = @actions ||= {}

    def sections
      if mode == :show
        SHOW_MENU
      else
        EPISODE_MENU
      end
    end

    def section(items)
      Gio::Menu.new.tap do |model|
        items.each do |label, action_name, target|
          model.append_item(menu_item(label, action_name, target))
        end
      end
    end

    def menu_item(label, action_name, target)
      Gio::MenuItem.new(label).tap do |item|
        item.set_action_and_target_value(action_name, GLib::Variant.new(target))
      end
    end

    def filter_changed
      update_active_circle
      @callbacks.each { |callback| callback.call(self) }
    end

    # Upstream's update_active_css: the dot is up whenever the filter is not
    # the default one.
    def update_active_circle
      is_active_circle.visible = !episode_filter.default?
    end

    def tristate(name)
      state(name).then do |value|
        if value == "yes"
          true
        elsif value == "no"
          false
        end
      end
    end
end
