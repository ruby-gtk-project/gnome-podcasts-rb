# frozen_string_literal: true

require "adwaita"
require_relative "base_view"
require_relative "dbqueries"
require_relative "episode_widget"

# QueueView is the Queue page: the episodes lined up to play, in order.
#
# Ported from podcasts-gtk/src/widgets/queue_view.rs and
# podcasts-gtk/resources/gtk/queue_view.ui: the scrolling base view, a 700px
# clamp, a boxed list of episode rows in queue order, and a "Queue Is Empty"
# status page in its place while there is nothing queued. The rows are built
# in queue mode, which is what gives them their drag handle and their
# move-in-queue menu items.
#
# The two in-place updates upstream makes rather than rebuilding the page —
# after a removal and after a move — are here too, including the focus they
# move to the row that took the place of the one that went away.
class QueueView
  CLAMP_SIZE = 700

  def initialize(app:)
    @app = app
    @rows = {}
  end

  attr_reader :app

  def build
    bin.tap do |root|
      root.child = base_view.build

      base_view.content = clamp

      clamp.tap do |clamped|
        clamped.child = frame_parent

        frame_parent.tap do |box|
          box.append(empty_status_page)
          box.append(queue_list)
        end
      end

      reload
    end
  end

  # Builds the rows from the queue; upstream makes a whole new QueueView for
  # this, the port refills the one list.
  def reload
    @rows = {}
    clear_list
    Dbqueries.queue.then do |items|
      if items.empty?
        enter_empty_state
      else
        leave_empty_state
        items.each { |item| append_row(item.episode_id) }
      end
    end
  end

  def update_episode(episode)
    @rows[episode.id].then do |widget|
      if widget
        widget.update_episode_state(episode)
      end
    end
  end

  def episode_widget(episode_id) = @rows[episode_id]

  # Upstream's update_queue_after_removal: drop the row, move the focus to
  # whatever took its place, and fall back to a full reload when the row is
  # not on the page.
  def update_after_removal(episode_id)
    @rows[episode_id].then do |widget|
      if widget.nil?
        false
      else
        remove_row(episode_id, widget)
        true
      end
    end
  end

  # Upstream's update_queue_after_move: take the row out and put it back at
  # its new index, keeping its focus.
  def update_after_move(episode_id, new_index)
    @rows[episode_id].then do |widget|
      if widget.nil? || new_index.nil?
        false
      else
        queue_list.remove(widget.row)
        queue_list.insert(widget.row, new_index)
        widget.row.grab_focus
        true
      end
    end
  end

  def bin = @bin ||= Adwaita::Bin.new
  def base_view = @base_view ||= BaseView.new

  def clamp
    @clamp ||= Adwaita::Clamp.new.tap do |clamped|
      clamped.maximum_size = CLAMP_SIZE
    end
  end

  def frame_parent
    @frame_parent ||= Gtk::Box.new(:vertical, 24).tap do |box|
      box.margin_start = 12
      box.margin_end = 12
      box.margin_top = 32
      box.margin_bottom = 32
      box.hexpand = true
    end
  end

  def empty_status_page
    @empty_status_page ||= Adwaita::StatusPage.new.tap do |page|
      page.hexpand = true
      page.vexpand = true
      page.visible = false
      page.title = "Queue Is Empty"
      page.description = "Add episodes from the New view or Shows views"
      page.icon_name = "view-list-symbolic"
    end
  end

  def queue_list
    @queue_list ||= Gtk::ListBox.new.tap do |list_box|
      list_box.hexpand = true
      list_box.activate_on_single_click = true
      list_box.selection_mode = :none
      list_box.add_css_class("boxed-list")
      list_box.signal_connect("row-activated") { |_, row| on_row_activated(row) }
    end
  end

  private

    def on_row_activated(row)
      @rows.each_value { |widget| app.go_to_episode_description(widget.episode) if widget.row.equal?(row) }
    end

    def append_row(episode_id)
      Dbqueries.episode_from_id(episode_id).then do |episode|
        EpisodeWidget.new(
          app:           app,
          episode:       episode,
          add_show_link: true,
          queue_view:    true,
        ).then do |widget|
          @rows[episode_id] = widget
          queue_list.append(widget.build)
        end
      end
    rescue KeyError
      # The episode went away under us; the queue row goes with it.
      Dbqueries.remove_queue_item(Dbqueries.queue_item(episode_id))
    end

    def remove_row(episode_id, widget)
      index_of(widget).then do |index|
        queue_list.remove(widget.row)
        @rows.delete(episode_id)
        focus_after_removal(index)
        if @rows.empty?
          enter_empty_state
        end
      end
    end

    def index_of(widget)
      rows_in_order.index(widget.row).to_i
    end

    def rows_in_order
      [].tap do |found|
        child = queue_list.first_child
        while child
          found << child
          child = child.next_sibling
        end
      end
    end

    def focus_after_removal(index)
      rows_in_order.then do |rows|
        (rows[index] || rows[index - 1] || rows.last).then do |row|
          if row
            row.grab_focus
          end
        end
      end
    end

    def clear_list
      while queue_list.first_child
        queue_list.remove(queue_list.first_child)
      end
    end

    def enter_empty_state
      queue_list.visible = false
      empty_status_page.visible = true
    end

    def leave_empty_state
      queue_list.visible = true
      empty_status_page.visible = false
    end
end
