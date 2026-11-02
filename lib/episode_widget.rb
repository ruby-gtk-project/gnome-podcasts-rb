# frozen_string_literal: true

require "adwaita"
require_relative "dbqueries"
require_relative "download_covers"
require_relative "download_manager"
require_relative "download_progress"
require_relative "episode_menu"
require_relative "utils"

# EpisodeWidget is one episode row: cover, title, date line, and the button
# that applies to the state it is in.
#
# Ported from podcasts-gtk/src/widgets/episode.rs and
# podcasts-gtk/resources/gtk/episode_widget.ui, keeping its structure — the
# revealer the queue's drag and drop hides the row inside, the two drop-target
# revealers above and below it, the 64px cover, the two-line title with the
# played checkmark beside it, the subtitle of date, duration and size, and the
# download progress bar under them — and its state machine:
#
#   no audio file          -> no buttons, subtitle only
#   downloading            -> progress bar, byte counter, cancel button
#   downloaded             -> subtitle, no queue button
#   not downloaded         -> "Add to Queue", which queues and downloads
#
# The two states that need a player, Playing and Playable's play button, are
# left out until lib/player.rb exists rather than shown as buttons that would
# do nothing; the same goes for the row's "open the episode description"
# activation, which arrives with lib/episode_description.rb.
class EpisodeWidget
  COVER_SIZE = 64
  # The cover's size plus its 6px margins, from the .ui file's comment.
  DROP_TARGET_HEIGHT = 76

  def initialize(app:, episode:, add_show_link: true, queue_view: false)
    @app = app
    @episode = episode
    @add_show_link = add_show_link
    @queue_view = queue_view
  end

  attr_reader :app, :episode

  def id = episode.id
  def queue_view? = @queue_view
  def add_show_link? = @add_show_link

  def build
    row.tap do
      main_revealer.tap do |revealer|
        revealer.child = outer_box

        outer_box.tap do |box|
          box.append(motion_top_revealer)
          box.append(content_box)
          box.append(motion_bottom_revealer)
        end
      end

      content_box.tap do |box|
        box.append(drag_handle)
        box.append(cover)
        DownloadCovers.load_widget_texture(
          cover,
          episode.show_id,
          COVER_SIZE,
          set_tooltip: true,
        )
        box.append(info_box)

        info_box.tap do |info|
          info.append(top_box)
          info.append(progress.build)

          top_box.tap do |top|
            top.append(label_box)
            top.append(button_box)

            label_box.tap do |labels|
              labels.append(title_box)
              labels.append(subtitle_box)

              title_box.tap do |titles|
                titles.append(title)
                titles.append(played_checkmark)
              end

              subtitle_box.tap do |subtitles|
                subtitles.append(subtitle)
                subtitles.append(download_progress_label)
              end
            end

            button_box.tap do |buttons|
              buttons.append(cancel_button)
              buttons.append(add_to_queue_button)

              cancel_button.signal_connect("clicked") { progress.cancel }
              add_to_queue_button.signal_connect("clicked") { on_add_to_queue }
            end
          end
        end
      end

      init_info
      init_progress
      init_context_menu
      init_drag_and_drop
      determine_buttons_state
    end
  end

  # Upstream's update_episode_state: re-read the row's state and move the
  # buttons to match.
  def update_episode_state(updated = nil)
    @episode = updated || Dbqueries.episode_from_id(id)
    init_info
    determine_buttons_state
  end

  # Upstream's set_played: a played episode is dimmed and gets a checkmark.
  def played=(value)
    if value
      title.add_css_class("dim-label")
    else
      title.remove_css_class("dim-label")
    end
    played_checkmark.visible = value
  end

  # Widgets

  def row
    @row ||= Gtk::ListBoxRow.new.tap do |list_row|
      list_row.child = main_revealer
    end
  end

  def main_revealer
    @main_revealer ||= Gtk::Revealer.new.tap do |revealer|
      revealer.reveal_child = true
      revealer.transition_type = :slide_down
    end
  end

  def outer_box = @outer_box ||= Gtk::Box.new(:vertical, 0)

  def motion_top_revealer
    @motion_top_revealer ||= drop_revealer(:slide_up, "drop-target-top")
  end

  def motion_bottom_revealer
    @motion_bottom_revealer ||= drop_revealer(:slide_down, "drop-target-bottom")
  end

  def content_box
    @content_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.valign = :center
      box.margin_start = 6
      box.margin_end = 6
      box.margin_top = 6
      box.margin_bottom = 6
    end
  end

  def drag_handle
    @drag_handle ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.vexpand = true
      box.append(drag_handle_image)
    end
  end

  def drag_handle_image
    @drag_handle_image ||= Gtk::Image.new(icon_name: "list-drag-handle-symbolic").tap do |image|
      image.pixel_size = 16
      image.halign = :center
      image.valign = :center
      image.margin_end = 6
      image.add_css_class("dimmed")
    end
  end

  # Upstream's set_cover: the 64px thumbnail, with the show's title as the
  # tooltip, over the fallback the row shows while it is being fetched.
  def cover
    @cover ||= Gtk::Image.new(icon_name: "image-missing-symbolic").tap do |image|
      image.pixel_size = COVER_SIZE
      image.set_size_request(COVER_SIZE, COVER_SIZE)
      image.halign = :center
      image.valign = :center
      image.add_css_class("rounded-small")
      image.accessible_role = :label
    end
  end

  def info_box
    @info_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.set_size_request(-1, COVER_SIZE)
      box.valign = :center
      box.margin_start = 6
      box.margin_end = 6
      box.hexpand = true
    end
  end

  def top_box
    @top_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
      box.margin_start = 6
      box.margin_end = 6
      box.margin_top = 6
      box.hexpand = true
      box.vexpand = true
    end
  end

  def label_box
    @label_box ||= Gtk::Box.new(:vertical, 6).tap do |box|
      box.halign = :start
      box.valign = :center
      box.hexpand = true
    end
  end

  def title_box
    @title_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
      box.halign = :start
    end
  end

  def subtitle_box = @subtitle_box ||= Gtk::Box.new(:horizontal, 0)

  def title
    @title ||= Gtk::Label.new.tap do |label|
      label.ellipsize = :end
      label.lines = 2
      label.wrap = true
      label.wrap_mode = :word_char
      label.xalign = 0
    end
  end

  def played_checkmark
    @played_checkmark ||= Gtk::Image.new(icon_name: "object-select-symbolic").tap do |image|
      image.tooltip_text = "You’ve already listened to this episode."
      image.visible = false
      image.add_css_class("dim-label")
    end
  end

  def subtitle
    @subtitle ||= Gtk::Label.new.tap do |label|
      label.xalign = 0.0
      label.single_line_mode = true
      label.add_css_class("caption")
    end
  end

  def download_progress_label
    @download_progress_label ||= Gtk::Label.new.tap do |label|
      label.xalign = 0.0
      label.single_line_mode = true
      label.visible = false
      label.add_css_class("caption")
    end
  end

  def button_box
    @button_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.halign = :end
    end
  end

  def cancel_button
    @cancel_button ||= Gtk::Button.new(icon_name: "media-playback-stop-symbolic").tap do |button|
      button.margin_top = 2
      button.receives_default = false
      button.tooltip_text = "Cancel the download process"
      button.halign = :center
      button.valign = :center
      button.visible = false
      button.add_css_class("flat")
    end
  end

  def add_to_queue_button
    @add_to_queue_button ||= Gtk::Button.new(icon_name: "list-add-symbolic").tap do |button|
      button.margin_bottom = 6
      button.receives_default = true
      button.tooltip_text = "Add to Queue"
      button.halign = :center
      button.valign = :center
      button.visible = false
      button.add_css_class("flat")
    end
  end

  def progress = @progress ||= DownloadProgress.new

  private

    def drop_revealer(transition, css_class)
      Gtk::Revealer.new.tap do |revealer|
        revealer.reveal_child = false
        revealer.transition_type = transition
        revealer.transition_duration = 150
        revealer.child = Adwaita::Bin.new.tap do |bin|
          bin.set_size_request(-1, DROP_TARGET_HEIGHT)
          bin.add_css_class("drop-target")
          bin.add_css_class(css_class)
        end
      end
    end

    # Upstream's init_info.
    def init_info
      title.label = episode.title
      subtitle.label = subtitle_text
      self.played = episode.played?
    end

    # Upstream's set_subtitle: date, then duration, then size, separated by
    # bullets, leaving out whatever the feed did not say.
    def subtitle_text
      [date_text, Utils.format_minutes(episode.duration), Utils.format_size(episode.length)]
        .compact
        .join(" • ")
    end

    # Upstream's get_date: the year is printed only for other years.
    def date_text
      episode.epoch.localtime.then do |stamp|
        if stamp.year == Time.now.year
          stamp.strftime("%-d %b")
        else
          stamp.strftime("%-d %b %Y")
        end
      end
    end

    def init_progress
      progress.init(id)
      progress.on_state_change { update_episode_state }
      progress.on_size_change { |local, total| update_progress_label(local, total) }
    end

    # Upstream binds the label to the bar's local_size property and formats
    # "downloaded / total" from it.
    def update_progress_label(local, total)
      download_progress_label.label = [
        Utils.format_size(local) || "0 B",
        Utils.format_size(total) || "0 B",
      ].join(" / ")
    end

    # Upstream's determine_buttons_state, minus the Playing branch that needs
    # the player.
    def determine_buttons_state
      if episode.uri.nil?
        state_no_uri
      elsif progress.check_if_downloading
        state_in_progress
      elsif episode.downloaded?
        state_playable
      else
        state_download
      end
    end

    # Upstream's state_no_uri: an episode with no enclosure has nothing to
    # download or queue.
    def state_no_uri
      cancel_button.visible = false
      add_to_queue_button.visible = false
      download_progress_label.visible = false
      update_progress_spacing(false)
    end

    def state_in_progress
      cancel_button.visible = true
      download_progress_label.visible = true
      subtitle.visible = false
      add_to_queue_button.visible = false
      update_progress_spacing(true)
    end

    def state_playable
      cancel_button.visible = false
      add_to_queue_button.visible = false
      download_progress_label.visible = false
      subtitle.visible = true
      update_progress_spacing(false)
    end

    # Upstream's state_download, where the queue page leaves the button out
    # because its episodes are queued already.
    def state_download
      cancel_button.visible = false
      add_to_queue_button.visible = !queue_view?
      download_progress_label.visible = false
      subtitle.visible = true
      update_progress_spacing(false)
    end

    # Only one line of title while the bar is up, so the row does not grow
    # past 64px.
    def update_progress_spacing(bar_visible)
      if bar_visible
        progress.progress_bar.set_size_request(-1, 8)
        title.wrap = false
        title.lines = 1
      else
        progress.progress_bar.set_size_request(-1, -1)
        title.wrap = true
        title.lines = 2
      end
    end

    # Upstream's add_to_queue handler: queue the episode and start its
    # download.
    def on_add_to_queue
      app.add_to_queue(id)
      app.download_episode(id)
    end

    # Upstream's init_context_menu: right click, long press and the Menu key
    # all pop the episode menu up where the pointer is.
    def init_context_menu
      row.add_controller(right_click_gesture)
      row.add_controller(long_press_gesture)
      row.add_controller(menu_key_controller)
    end

    def right_click_gesture
      Gtk::GestureClick.new.tap do |gesture|
        gesture.button = Gdk::BUTTON_SECONDARY
        gesture.signal_connect("pressed") { |_, _, x, y| popup_menu(x, y) }
      end
    end

    def long_press_gesture
      Gtk::GestureLongPress.new.tap do |gesture|
        gesture.signal_connect("pressed") { |_, x, y| popup_menu(x, y) }
      end
    end

    def menu_key_controller
      Gtk::EventControllerKey.new.tap do |controller|
        controller.signal_connect("key-released") do |_, key, _code, _state|
          if key == Gdk::Keyval::KEY_Menu
            popup_menu(25, 40)
          end
        end
      end
    end

    def popup_menu(pos_x, pos_y)
      show_id = nil
      if add_show_link?
        show_id = episode.show_id
      end

      EpisodeMenu.new(
        app:        app,
        episode:    Dbqueries.episode_from_id(id),
        show_id:    show_id,
        queue_view: queue_view?,
      ).build.popover_at(row, pos_x, pos_y)
    end

    # Upstream's init_drag_and_drop: the handle is a drag source on the queue
    # page only, and the row is a drop target that reorders the queue.
    def init_drag_and_drop
      unless queue_view?
        drag_handle.visible = false
      end

      if queue_view?
        drag_handle.add_controller(drag_source)
        row.add_controller(drop_target)
        row.add_controller(drop_motion_controller)
      end
    end

    def drag_source
      Gtk::DragSource.new.tap do |source|
        source.actions = :move
        source.signal_connect("prepare") do
          Gdk::ContentProvider.new(GLib::Value.new(GLib::Type["gint"], id))
        end
        source.signal_connect("drag-begin") { main_revealer.reveal_child = false }
        source.signal_connect("drag-end") { drag_end }
        source.signal_connect("drag-cancel") { drag_end }
      end
    end

    def drag_end
      main_revealer.reveal_child = true
      clear_motion_revealers
    end

    def drop_target
      Gtk::DropTarget.new(GLib::Type["gint"], :move).tap do |target|
        target.signal_connect("drop") do |_, value, _x, drop_y|
          on_drop(value, bottom_half?(drop_y))
        end
      end
    end

    def drop_motion_controller
      Gtk::DropControllerMotion.new.tap do |controller|
        controller.signal_connect("motion") do |_, _x, motion_y|
          bottom_half?(motion_y).then do |bottom|
            motion_top_revealer.reveal_child = !bottom
            motion_bottom_revealer.reveal_child = bottom
          end
        end
        controller.signal_connect("leave") { clear_motion_revealers }
      end
    end

    def bottom_half?(pos_y) = pos_y >= row.allocated_height / 2.0

    def on_drop(value, bottom_target)
      clear_motion_revealers
      value.to_i.then do |dropped_id|
        app.move_to_position_in_queue(dropped_id, id, bottom_target)
        true
      end
    end

    def clear_motion_revealers
      motion_top_revealer.reveal_child = false
      motion_bottom_revealer.reveal_child = false
    end
end
