# frozen_string_literal: true

require "adwaita"
require_relative "dbqueries"
require_relative "download_covers"
require_relative "download_manager"
require_relative "download_progress"
require_relative "episode_description_parser"
require_relative "episode_menu"
require_relative "utils"

# EpisodeDescription is the page an episode row opens: its cover, title,
# podcast name, duration and date, full description, and the buttons that
# apply to whatever state the episode is in.
#
# Ported from podcasts-gtk/src/widgets/episode_description.rs and
# podcasts-gtk/resources/gtk/episode_description.ui: a navigation page whose
# toolbar view holds a header bar with the episode menu button, over a 700px
# clamp of the cover/title/duration row, the download button row, and the
# description label, with the episode-specific cover picture appearing below
# the description when the feed gives one that differs from the show's.
#
# Upstream's stream/play/pause buttons and determine_button_state's Playing
# branch all need lib/player.rb, which does not exist in this port yet; they
# are left out the same way episode_widget.rb leaves them out, rather than
# shown as buttons that would do nothing.
class EpisodeDescription
  TAG = "episode-description"
  CLAMP_SIZE = 700
  COVER_SIZE = 64
  EPISODE_COVER_HEIGHT = 300

  def initialize(app:, episode:, show:)
    @app = app
    @episode = episode
    @show = show
  end

  attr_reader :app, :episode, :show

  def id = episode.id

  def build
    page.tap do
      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = scrolled_window

        header_bar.tap do |header|
          header.pack_end(menu_button)
          menu_button.menu_model = episode_menu.build.menu
        end

        scrolled_window.child = clamp
        clamp.child = content_box

        content_box.tap do |box|
          box.append(episode_info)
          box.append(description)
          box.append(episode_specific_cover)

          episode_info.tap do |info|
            info.append(episode_info_horizontal)
            info.append(button_row)

            episode_info_horizontal.tap do |horizontal|
              horizontal.append(cover)
              horizontal.append(title_box)

              title_box.tap do |titles|
                titles.append(podcast_title)
                titles.append(episode_title)
                titles.append(episode_duration)
              end
            end

            button_row.tap do |row|
              row.append(button_box)

              button_box.tap do |buttons|
                buttons.append(download_button)
                buttons.append(cancel_button)
                buttons.append(delete_button)

                download_button.signal_connect("clicked") { on_download }
                cancel_button.signal_connect("clicked") { progress.cancel }
                delete_button.signal_connect("clicked") { on_delete }
              end
            end
          end
        end
      end

      window.insert_action_group("episode", episode_menu.group)

      description.signal_connect("activate-link") { |_, uri| on_description_link(uri) }

      init_info
      init_progress
      determine_button_state
    end
  end

  # Upstream's update_episode: the buttons move to match a fresh read of the
  # episode without touching the text, which the row's own refresh updates
  # separately through refresh_episode.
  def update_episode(updated_episode = nil)
    @episode = updated_episode || Dbqueries.episode_from_id(id)
    determine_button_state
  end

  # Adwaita::NavigationPage takes its child positionally, so the toolbar view
  # is built before the page that holds it.
  def page
    @page ||= Adwaita::NavigationPage.new(toolbar_view, episode.title).tap do |navigation_page|
      navigation_page.tag = TAG
      navigation_page.add_css_class("episode_description")
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def menu_button
    @menu_button ||= Gtk::MenuButton.new.tap do |button|
      button.primary = true
      button.icon_name = "view-more-symbolic"
      button.tooltip_text = "Episode Menu"
    end
  end

  def scrolled_window
    @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |win|
      win.vexpand = true
      win.hexpand = true
    end
  end

  def clamp
    @clamp ||= Adwaita::Clamp.new.tap do |clamped|
      clamped.vexpand = true
      clamped.maximum_size = CLAMP_SIZE
    end
  end

  def content_box
    @content_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.vexpand = true
      box.baseline_position = :top
    end
  end

  def episode_info
    @episode_info ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.valign = :start
      box.margin_top = 18
      box.margin_bottom = 18
      box.hexpand = true
    end
  end

  def episode_info_horizontal
    @episode_info_horizontal ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.margin_start = 18
      box.margin_end = 14
    end
  end

  def cover
    @cover ||= Gtk::Image.new(icon_name: "image-missing-symbolic").tap do |image|
      image.margin_top = 4
      image.margin_end = 12
      image.hexpand = false
      image.vexpand = false
      image.valign = :start
      image.pixel_size = COVER_SIZE
      image.add_css_class("rounded-small")
    end
  end

  def title_box = @title_box ||= Gtk::Box.new(:vertical, 0)

  def podcast_title
    @podcast_title ||= Gtk::Label.new.tap do |label|
      label.wrap = true
      label.wrap_mode = :word_char
      label.xalign = 0
      label.add_css_class("dim-label")
    end
  end

  def episode_title
    @episode_title ||= Gtk::Label.new.tap do |label|
      label.wrap = true
      label.wrap_mode = :word_char
      label.lines = 1
      label.xalign = 0
      label.add_css_class("heading")
    end
  end

  def episode_duration
    @episode_duration ||= Gtk::Label.new.tap do |label|
      label.xalign = 0
    end
  end

  def button_row = @button_row ||= Gtk::Box.new(:horizontal, 0).tap { |box| box.add_css_class("button-row") }

  def button_box
    @button_box ||= Gtk::Box.new(:horizontal, 10).tap do |box|
      box.margin_start = 18
      box.margin_end = 18
      box.halign = :start
      box.homogeneous = true
    end
  end

  def download_button
    @download_button ||= pill_button("document-save-symbolic", "_Download")
  end

  def delete_button
    @delete_button ||= pill_button("user-trash-symbolic", "Delete")
  end

  def cancel_button
    @cancel_button ||= Gtk::Button.new.tap do |button|
      button.add_css_class("pill")
      button.add_css_class("cancel-button")
      button.visible = false
      button.width_request = 145
      button.overflow = :hidden
      button.child = cancel_button_content
    end
  end

  def cancel_button_content
    @cancel_button_content ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.append(cancel_button_label_box)
      box.append(progress.build)
    end
  end

  def cancel_button_label_box
    @cancel_button_label_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.add_css_class("cancel-button-text")
      box.halign = :center
      box.append(Gtk::Label.new("Cancel").tap { |label| label.ellipsize = :end })
    end
  end

  def description
    @description ||= Gtk::Label.new.tap do |label|
      label.valign = :start
      label.margin_start = 18
      label.margin_end = 18
      label.margin_bottom = 18
      label.wrap = true
      label.wrap_mode = :word_char
      label.xalign = 0
      label.add_css_class("episode_description_label")
      label.add_css_class("document")
    end
  end

  # Upstream shows an episode-specific image, fetched separately from the
  # show's own cover, when the feed gives one that differs from it. That
  # fetch needs download_covers.rb machinery this port has not built for a
  # single arbitrary image url yet, so the picture stays in the layout, where
  # it keeps upstream's default of invisible, but nothing sets it.
  def episode_specific_cover
    @episode_specific_cover ||= Gtk::Picture.new.tap do |picture|
      picture.margin_start = 18
      picture.margin_end = 18
      picture.margin_bottom = 18
      picture.hexpand = true
      picture.vexpand = true
      picture.visible = false
      picture.content_fit = :scale_down
      picture.valign = :start
      picture.halign = :fill
      picture.set_size_request(-1, EPISODE_COVER_HEIGHT)
      picture.tooltip_text = "Episode Cover"
    end
  end

  def progress = @progress ||= DownloadProgress.new
  def window = app.window

  def episode_menu
    @episode_menu ||= EpisodeMenu.new(app: app, episode: episode, show_id: show.id, queue_view: false)
  end

  private

    def pill_button(icon_name, label_text)
      Gtk::Button.new.tap do |button|
        button.add_css_class("pill")
        button.visible = false
        button.width_request = 145
        button.child = Adwaita::ButtonContent.new.tap do |content|
          content.icon_name = icon_name
          content.label = label_text
          content.use_underline = true
          content.can_shrink = true
        end
      end
    end

    def init_info
      podcast_title.label = show.title
      episode_title.label = episode.title
      episode_duration.label = duration_date_text
      set_cover
      set_description
    end

    def set_cover
      DownloadCovers.load_widget_texture(cover, episode.show_id, COVER_SIZE, set_tooltip: true)
    end

    # Upstream's set_description: Pango markup from the parser, falling back
    # to the feed's plain text if that markup turns out invalid.
    def set_description
      episode.description.then do |text|
        if text
          markup = EpisodeDescriptionParser.html_to_pango_markup(text)
          begin
            description.markup = markup
          rescue StandardError
            description.text = text
          end
        end
      end
    end

    # Upstream's set_duration: duration then date, separated by a bullet,
    # with the year shown only when it is not the current one.
    def duration_date_text
      [Utils.format_duration(episode.duration), date_text].compact.join(" • ")
    end

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
      progress.on_state_change { determine_button_state }
    end

    # Upstream's determine_button_state minus the Playing branch, which needs
    # the player.
    def determine_button_state
      is_downloading = progress.check_if_downloading
      is_downloaded = episode.downloaded?
      cancel_button.visible = is_downloading
      download_button.visible = !is_downloaded && !is_downloading
      delete_button.visible = is_downloaded
    end

    def on_download
      app.download_episode(id)
      determine_button_state
    end

    def on_delete
      app.delete_episode_download(id)
      determine_button_state
    end

    # Upstream's description.connect_activate_link: a "jump:seconds" link
    # seeks the player, which does not exist in this port yet, so it is left
    # unhandled and GTK opens anything else (a real url) itself.
    def on_description_link(uri)
      if uri.start_with?("jump:")
        true
      else
        false
      end
    end
end
