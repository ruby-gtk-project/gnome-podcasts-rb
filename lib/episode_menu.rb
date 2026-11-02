# frozen_string_literal: true

require "gtk4"
require_relative "dbqueries"

# EpisodeMenu is the context menu of an episode row.
#
# Ported from podcasts-gtk/src/widgets/episode_menu.rs and
# podcasts-gtk/resources/gtk/episode_menu.ui. The structure is upstream's: one
# menu model with two sections, an "episode" action group, and an item that
# hides itself when its action is missing or disabled. Upstream only adds the
# actions that apply to this episode — no url means no "Copy Episode URL", an
# already downloaded file means "Delete" instead of "Download" — and the menu
# items follow, so the port adds them the same way.
class EpisodeMenu
  MAIN_SECTION = [
    # Translators: Show as a noun, meaning a Podcast-Show.
    ["Go to Show", "episode.go-to-show", "action-missing"],
    ["Copy Episode URL", "episode.copy-episode-url", "action-disabled"],
    ["Mark as Played", "episode.mark-as-played", "action-disabled"],
    ["Mark as Unplayed", "episode.mark-as-unplayed", "action-disabled"],
    ["Download", "episode.download", "action-disabled"],
    ["Delete", "episode.delete", "action-disabled"],
  ].freeze

  QUEUE_SECTION = [
    ["Move Up in Queue", "episode.move-up-in-queue", "action-disabled"],
    ["Move Down in Queue", "episode.move-down-in-queue", "action-disabled"],
  ].freeze

  # `app` is the application, which is where upstream's Action channel goes.
  def initialize(app:, episode:, show_id: nil, queue_view: false)
    @app = app
    @episode = episode
    @show_id = show_id
    @queue_view = queue_view
  end

  attr_reader :app, :episode, :show_id

  def queue_view? = @queue_view

  # Builds the actions this episode supports and answers self.
  def build
    tap do
      if show_id
        add_action("go-to-show") { app.go_to_show_by_id(show_id) }
      end

      add_mark_actions
      add_url_action
      add_file_actions
      add_queue_actions
    end
  end

  # The popover upstream pops up at the pointer, parented on the row.
  def popover_at(widget, x, y)
    popover.tap do |menu_popover|
      menu_popover.parent = widget
      menu_popover.insert_action_group("episode", group)
      menu_popover.pointing_to = Gdk::Rectangle.new(
        x.to_i,
        y.to_i,
        1,
        1,
      )
      menu_popover.popup
    end
  end

  def popover
    @popover ||= Gtk::PopoverMenu.new(menu).tap do |menu_popover|
      menu_popover.halign = :start
      menu_popover.has_arrow = false
    end
  end

  def menu
    @menu ||= Gio::Menu.new.tap do |model|
      model.append_section(nil, section(MAIN_SECTION))
      model.append_section(nil, section(QUEUE_SECTION))
    end
  end

  def group = @group ||= Gio::SimpleActionGroup.new

  private

    def add_mark_actions
      add_action("mark-as-played", enabled: !episode.played?) do
        app.mark_as_played(true, episode.id)
      end
      add_action("mark-as-unplayed", enabled: episode.played?) do
        app.mark_as_played(false, episode.id)
      end
    end

    def add_url_action
      if episode.uri
        add_action("copy-episode-url") { app.copy_url(episode.id) }
      end
    end

    # Upstream offers "Download" while there is no file and "Delete" once
    # there is one.
    def add_file_actions
      if episode.uri && !episode.downloaded?
        add_action("download") { app.download_episode(episode.id) }
      end

      if episode.downloaded?
        add_action("delete") { app.delete_episode_download(episode.id) }
      end
    end

    # The queue moves are offered on the queue page only, and only where there
    # is somewhere to move to.
    def add_queue_actions
      if queue_view?
        unless Dbqueries.first_position_in_queue?(episode.id)
          add_action("move-up-in-queue") { app.move_up_in_queue(episode.id) }
        end

        unless Dbqueries.last_position_in_queue?(episode.id)
          add_action("move-down-in-queue") { app.move_down_in_queue(episode.id) }
        end
      end
    end

    def add_action(name, enabled: true, &block)
      Gio::SimpleAction.new(name).tap do |action|
        action.enabled = enabled
        action.signal_connect("activate") { block.call }
        group.add_action(action)
      end
    end

    def section(items)
      Gio::Menu.new.tap do |model|
        items.each { |label, action_name, hidden_when| model.append_item(item(label, action_name, hidden_when)) }
      end
    end

    def item(label, action_name, hidden_when)
      Gio::MenuItem.new(label, action_name).tap do |menu_item|
        menu_item.set_attribute_value("hidden-when", GLib::Variant.new(hidden_when))
      end
    end
end
