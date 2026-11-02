# frozen_string_literal: true

require "adwaita"
require "gtk4"
require "uri"
require_relative "dbqueries"
require_relative "discovery"
require_relative "utils"

# DiscoveryPage is the "Add Podcasts" page: a search box over the platforms
# the user has switched on, and a switch per platform.
#
# Ported from podcasts-gtk/src/widgets/discovery_page.rs and
# podcasts-gtk/resources/gtk/discovery_page.ui: a navigation page tagged
# "discovery" with a toolbar view, a header bar, and a scrolling clamp of
# 700px around a boxed-list column — the "Search" heading, the line explaining
# what the box takes, the entry with its submit button and the spinner that
# replaces it while a search is running, the error line for when no platform
# is on, and the preferences group of platform switches under all of it.
#
# What the entry does depends on what is in it. Text that parses as a url is
# subscribed to directly, after the two rewrites upstream does first — an
# iTunes podcast page and a SoundCloud page both become the feed they stand
# for. Anything else is a search, and its results are pushed as
# DiscoverySearchResults.
#
# The work runs on a thread and the outcome is applied on the main loop, where
# upstream spawns onto its tokio runtime and sends the outcome back down a
# channel.
class DiscoveryPage
  TAG = "discovery"
  TITLE = "Add Podcasts"
  CLAMP_SIZE = 700
  TICK = 100

  def initialize(app:)
    @app = app
  end

  attr_reader :app

  def build
    page.tap do
      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = scrolled_window

        scrolled_window.child = clamp
        clamp.child = container

        container.tap do |box|
          box.append(search_heading)
          box.append(entry_description)
          box.append(entry_box)
          box.append(no_platforms_selected_label)
          box.append(platform_group)

          entry_box.tap do |entries|
            entries.append(entry)
            entries.append(search_button)
            entries.append(loading_spinner)

            entry.signal_connect("activate") { on_activate }
            search_button.signal_connect("clicked") { entry.signal_emit("activate") }
          end

          Discovery::ALL_PLATFORM_IDS.each do |id|
            platform_group.add(platform_switch(id))
          end
        end
      end
    end
  end

  # Adwaita::NavigationPage takes its child positionally, so the toolbar view
  # is built before the page that holds it.
  def page
    @page ||= Adwaita::NavigationPage.new(toolbar_view, TITLE).tap do |navigation_page|
      navigation_page.tag = TAG
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def scrolled_window
    @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |window|
      window.vexpand = true
      window.hexpand = true
      window.hscrollbar_policy = :never
    end
  end

  def clamp
    @clamp ||= Adwaita::Clamp.new.tap do |clamped|
      clamped.vexpand = true
      clamped.maximum_size = CLAMP_SIZE
    end
  end

  def container
    @container ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.vexpand = true
      box.margin_top = 18
      box.margin_bottom = 18
      box.margin_start = 18
      box.margin_end = 18
      box.add_css_class("boxed-list")
    end
  end

  # Translators: Noun, headline for a page on that you search on iTunes/fyyd.
  def search_heading
    @search_heading ||= Gtk::Label.new("Search").tap do |label|
      label.halign = :start
      label.add_css_class("heading")
    end
  end

  def entry_description
    @entry_description ||= Gtk::Label.new(
      "Enter a feed URL or search the selected platforms.",
    ).tap do |label|
      label.xalign = 0
      label.wrap = true
      label.justify = :left
      label.margin_top = 8
      label.margin_bottom = 8
      label.add_css_class("dim-label")
    end
  end

  def entry_box
    @entry_box ||= Gtk::Box.new(:horizontal, 10).tap do |box|
      box.halign = :fill
    end
  end

  def entry
    @entry ||= Gtk::Entry.new.tap do |text_entry|
      text_entry.hexpand = true
      text_entry.truncate_multiline = true
      text_entry.receives_default = true
    end
  end

  def search_button
    @search_button ||= Gtk::Button.new.tap do |button|
      button.tooltip_text = "Submit search"
      button.icon_name = "system-search-symbolic"
    end
  end

  def loading_spinner
    @loading_spinner ||= Adwaita::Spinner.new.tap do |spinner|
      spinner.tooltip_text = "Loading…"
      spinner.visible = false
      spinner.width_request = 24
      spinner.margin_start = 10
    end
  end

  def no_platforms_selected_label
    @no_platforms_selected_label ||= Gtk::Label.new(
      "Please enable a Search Platform below, or enter a http(s) feed URL.",
    ).tap do |label|
      label.visible = false
      label.halign = :start
      label.margin_top = 8
      label.wrap = true
      label.add_css_class("error")
    end
  end

  # Translators: Headline for a list of services to search new podcasts like
  # iTunes, fyyd, etc., ...
  def platform_group
    @platform_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.margin_top = 18
      group.title = "Search Platforms"
      group.description = "Search queries will be sent to these platforms."
    end
  end

  # One switch per platform, set from the row the last session wrote and
  # writing it back as it is flipped.
  def platform_switch(id)
    switches[id] ||= Adwaita::SwitchRow.new.tap do |row|
      row.title = id
      row.selectable = false
      row.active = settings.fetch(id, false) == true
      row.signal_connect("notify::active") { on_platform_toggled(row) }
    end
  end

  private

    def switches = @switches ||= {}
    def settings = @settings ||= Dbqueries.discovery_settings
    def outcomes = @outcomes ||= Thread::Queue.new

    def on_platform_toggled(row)
      Dbqueries.set_discovery_setting(row.title, row.active?)
      if row.active?
        entry.remove_css_class("error")
        no_platforms_selected_label.visible = false
      end
    rescue StandardError => e
      warn "failed setting search preference: #{e.message}"
    end

    # Upstream's entry activate handler.
    def on_activate
      entry.text.to_s.then do |text|
        start_loading
        Thread.new { outcomes.push(run(text)) }
        GLib::Timeout.add(TICK) { tick }
      end
    end

    def start_loading
      search_button.visible = false
      loading_spinner.visible = true
      entry.remove_css_class("error")
      no_platforms_selected_label.visible = false
    end

    def tick
      if outcomes.empty?
        true
      else
        finish(outcomes.pop)
        false
      end
    end

    # Upstream's loading_done receiver: the spinner goes away whatever
    # happened, and only "no platform selected" marks the entry.
    def finish(outcome)
      search_button.visible = true
      loading_spinner.visible = false
      apply(outcome)
    end

    def apply(outcome)
      case outcome.first
      when :results then app.go_to_found_podcasts(outcome.last)
      when :subscribed then subscribed(outcome.last)
      when :no_platforms then no_platforms
      when :error then app.error_notification(outcome.last)
      end
    end

    def subscribed(subscription)
      if subscription.show
        app.refresh_all_views
        app.go_to_show(subscription.show)
      else
        app.error_notification(subscription.error)
      end
    end

    def no_platforms
      entry.add_css_class("error")
      no_platforms_selected_label.visible = true
    end

    # The worker's whole job: a url is subscribed to, anything else searched
    # for. Answers what the main loop should do with the result.
    def run(text)
      if url?(text)
        [:subscribed, Utils.subscribe(resolved_url(text))]
      else
        [:results, Discovery.search(text)]
      end
    rescue Discovery::NoSearchPlatformsSelected
      [:no_platforms, nil]
    rescue StandardError => e
      warn "Discovery failed: #{text} #{e.message}"
      [:error, e.message]
    end

    # Upstream reaches add_podcast_from_url only when Url::parse succeeded,
    # which needs a scheme; text without one is a search term.
    def url?(text)
      !URI.parse(text).scheme.nil?
    rescue URI::InvalidURIError
      false
    end

    # Upstream's add_podcast_from_url: the two platform pages that are not
    # feeds become the feeds they stand for.
    def resolved_url(text)
      schemed(text).then do |url|
        if url.include?("itunes.com") || url.include?("apple.com")
          Utils.itunes_to_rss(url)
        elsif url.include?("soundcloud.com") && !url.include?("feeds.soundcloud.com")
          Utils.soundcloud_to_rss(url)
        else
          url
        end
      end
    end

    def schemed(text)
      if text.start_with?("https://", "http://")
        text
      else
        "http://#{text}"
      end
    end
end
