# frozen_string_literal: true

require "fileutils"
require "gdk_pixbuf2"
require "gtk4"
require "adwaita"
require_relative "http"
require_relative "utils"
require_relative "xdg_dirs"

# DiscoveryFoundPodcast is one row of a search result: the cover, the title
# and author, a line of the description, the feed url, the episode count, the
# date of the last episode, and a Subscribe button.
#
# Ported from podcasts-gtk/resources/gtk/discovery_found_podcast.ui and the
# `PodcastPriv` half of podcasts-gtk/src/widgets/discovery_search_results.rs.
# The row is upstream's AdwPreferencesRow with a three-part box inside it —
# the 64px cover, the text column, and a stack that holds the Subscribe button
# and the spinner it is swapped for while the feed is being fetched.
#
# The art is fetched straight from the url the platform gave, not through
# lib/download_covers.rb, because the show has no row to cache it against yet;
# that is upstream's choice too. The fetch runs on a thread and the texture is
# made on the main loop, since GDK objects belong there.
class DiscoveryFoundPodcast
  COVER_SIZE = 64
  TICK = 100
  # Upstream's "%e %b %Y", formatted the same way without a locale.
  DATE_FORMAT = "%e %b %Y"

  def initialize(app:, podcast:)
    @app = app
    @podcast = podcast
  end

  attr_reader :app, :podcast

  def build
    row.tap do
      content_box.tap do |box|
        box.append(cover)
        box.append(text_box)
        box.append(subscribe_stack)

        text_box.tap do |text|
          text.append(title_label)
          text.append(author_label)
          text.append(description_label)
          text.append(episode_count_box)
          text.append(url_box)

          episode_count_box.tap do |count|
            count.append(episode_count_title)
            count.append(episode_count_label)
          end

          url_box.tap do |urls|
            urls.append(feed_url_label)
            urls.append(last_publication_label)
          end
        end

        subscribe_stack.tap do |stack|
          stack.add_child(subscribe_button)
          stack.add_child(loading_spinner)

          subscribe_button.signal_connect("clicked") { on_subscribe }
        end
      end

      fill
      load_art
    end
  end

  # Upstream's PodcastPriv::init: everything the platform answered with, and
  # the three lines upstream only reveals when it has something to put in
  # them.
  #
  # One correction: upstream reveals `episode_count_label`, which its .ui file
  # already has visible, and leaves the box around it hidden — so the count
  # never appears. The box is what gets revealed here.
  def fill
    title_label.text = podcast.title
    author_label.text = podcast.author
    feed_url_label.text = podcast.feed

    podcast.description.strip.then do |description|
      unless description.empty?
        description_label.text = description
        description_label.tooltip_text = description
        description_label.visible = true
      end
    end

    if podcast.episode_count
      episode_count_label.text = podcast.episode_count.to_s
      episode_count_box.visible = true
    end

    if podcast.last_publication
      last_publication_label.text = podcast.last_publication.strftime(DATE_FORMAT).strip
      last_publication_label.visible = true
    end
  end

  def row
    @row ||= Adwaita::PreferencesRow.new.tap do |preferences_row|
      preferences_row.selectable = false
      preferences_row.child = content_box
      preferences_row.add_css_class("found-podcast")
    end
  end

  def content_box
    @content_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.margin_start = 15
      box.margin_end = 15
      box.margin_top = 15
      box.margin_bottom = 15
      box.vexpand = false
      box.hexpand = true
    end
  end

  def cover
    @cover ||= Gtk::Image.new(icon_name: "image-missing-symbolic").tap do |image|
      image.pixel_size = COVER_SIZE
      image.set_size_request(COVER_SIZE, COVER_SIZE)
      image.accessible_role = :presentation
      image.valign = :start
    end
  end

  def text_box
    @text_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.margin_start = 15
      box.margin_end = 15
    end
  end

  def title_label
    @title_label ||= Gtk::Label.new.tap do |label|
      label.halign = :start
      label.wrap = true
      label.add_css_class("title")
    end
  end

  def author_label
    @author_label ||= Gtk::Label.new.tap do |label|
      label.halign = :start
      label.ellipsize = :end
      label.margin_bottom = 10
      label.add_css_class("subtitle")
    end
  end

  def description_label
    @description_label ||= Gtk::Label.new.tap do |label|
      label.halign = :start
      label.ellipsize = :end
      label.vexpand = false
      label.single_line_mode = true
      label.visible = false
      label.add_css_class("dim-label")
    end
  end

  def episode_count_box
    @episode_count_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.hexpand = true
      box.valign = :end
      box.visible = false
    end
  end

  # Translators: Noun, the number of episodes a found podcast has.
  def episode_count_title
    @episode_count_title ||= Gtk::Label.new("Episodes: ").tap do |label|
      label.justify = :right
      label.xalign = 1
      label.add_css_class("subtitle")
    end
  end

  def episode_count_label
    @episode_count_label ||= Gtk::Label.new("0").tap do |label|
      label.add_css_class("subtitle")
    end
  end

  def url_box
    @url_box ||= Gtk::Box.new(:horizontal, 15)
  end

  def feed_url_label
    @feed_url_label ||= Gtk::Label.new.tap do |label|
      label.valign = :end
      label.halign = :start
      label.ellipsize = :end
      label.vexpand = false
      label.margin_top = 10
      label.single_line_mode = true
      label.add_css_class("subtitle")
    end
  end

  def last_publication_label
    @last_publication_label ||= Gtk::Label.new.tap do |label|
      label.visible = false
      label.tooltip_text = "Last publication"
      label.valign = :end
      label.halign = :end
      label.vexpand = false
      label.hexpand = true
      label.margin_top = 10
      label.single_line_mode = true
      label.add_css_class("subtitle")
    end
  end

  def subscribe_stack
    @subscribe_stack ||= Gtk::Stack.new.tap do |stack|
      stack.hhomogeneous = true
      stack.vhomogeneous = true
    end
  end

  def subscribe_button
    @subscribe_button ||= Gtk::Button.new(label: "_Subscribe").tap do |button|
      button.use_underline = true
      button.can_shrink = true
      button.valign = :center
      button.halign = :end
      button.receives_default = true
    end
  end

  def loading_spinner
    @loading_spinner ||= Adwaita::Spinner.new.tap do |spinner|
      spinner.tooltip_text = "Subscribing to feed…"
      spinner.valign = :center
      spinner.halign = :center
    end
  end

  private

    def subscriptions = @subscriptions ||= Thread::Queue.new
    def art_results = @art_results ||= Thread::Queue.new

    # Upstream swaps the stack to the spinner, subscribes off the main thread
    # and swaps back when it is done.
    def on_subscribe
      subscribe_stack.visible_child = loading_spinner
      Thread.new { subscriptions.push(Utils.subscribe(podcast.feed)) }
      GLib::Timeout.add(TICK) { subscribe_tick }
    end

    def subscribe_tick
      if subscriptions.empty?
        true
      else
        subscribed(subscriptions.pop)
        false
      end
    end

    # Upstream's subscribe sends these down the channel from the worker; here
    # the worker hands back the outcome and this applies it.
    def subscribed(subscription)
      subscribe_stack.visible_child = subscribe_button
      if subscription.show
        app.refresh_all_views
        app.go_to_show(subscription.show)
      else
        app.error_notification(subscription.error)
      end
    end

    def load_art
      unless podcast.art.empty?
        Thread.new { art_results.push(fetch_art) }
        GLib::Timeout.add(TICK) { art_tick }
      end
    end

    def fetch_art
      File.join(XdgDirs.tmp, "discovery-#{object_id}.part").tap do |path|
        File.open(path, "wb") { |file| file.write(Http.get(podcast.art)) }
      end
    rescue StandardError => e
      warn "failed to load image for search result: #{podcast.art} #{e.message}"
      nil
    end

    def art_tick
      if art_results.empty?
        true
      else
        art_results.pop.then do |path|
          if path
            apply_art(path)
          end
        end
        false
      end
    end

    def apply_art(path)
      cover.paintable = Gdk::Texture.new(GdkPixbuf::Pixbuf.new(file: path))
    rescue StandardError => e
      warn "failed to load image for search result: #{podcast.art} #{e.message}"
    ensure
      FileUtils.rm_f(path)
    end
end
