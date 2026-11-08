# frozen_string_literal: true

# Drives the discovery pages: opens "Add Podcasts" from the header button's
# action, flips the platform switches, checks that the entry refuses a search
# with every platform off, and renders a page of made-up search results.
#
# Run it from the dev shell:
#   xvfb-run ruby test/drive_discovery.rb
#
# It writes PNGs under tmp/shots and exits non-zero if any check fails. It
# never reaches the network: the search path it exercises is the one that
# fails before any request is sent, and the result rows are built from
# FoundPodcasts made here.

require "tmpdir"

ROOT = Dir.mktmpdir("gnome-podcasts-discovery")
ENV["XDG_DATA_HOME"] = File.join(ROOT, "data")
ENV["XDG_CONFIG_HOME"] = File.join(ROOT, "config")
ENV["XDG_CACHE_HOME"] = File.join(ROOT, "cache")

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "gnome_podcasts"
require "discovery"
require "discovery_page"
require "discovery_search_results"
require "episode_description_parser"

require_relative "gtk_driver"

SETTINGS = Settings.new(path: File.join(ROOT, "settings.json"))
SETTINGS["refresh-on-startup"] = false
SETTINGS["refresh-interval"] = false

APP = GnomePodcasts::Application.new(settings: SETTINGS)

RESULTS = [
  Discovery::FoundPodcast.new(
    feed:             "https://feeds.fireside.fm/cornerspaeti/rss",
    title:            "Corner Späti",
    author:           "The Späti Boys",
    description:      "Weekly discussions of a deteriorating world.",
    art:              "",
    episode_count:    348,
    last_publication: Time.at(1_709_802_000),
  ),
  Discovery::FoundPodcast.new(
    feed:             "https://feeds.fireside.fm/cornerspaeti/rss/",
    title:            "Corner Späti (duplicate feed)",
    author:           "The Späti Boys",
    description:      "A longer description than the one above, so a merge keeps it.",
    art:              "",
    episode_count:    12,
    last_publication: nil,
  ),
].freeze

GtkDriver.drive(APP, shots: "tmp/shots") do |d, app|
  d.window { app.window }

  d.step("the description parser turns HTML into Pango markup") do
    EpisodeDescriptionParser.html_to_pango_markup(
      "<p>Hear it at 1:02:03 or read <a href=\"https://example.com/a\">the notes</a>.</p>",
    ).then do |markup|
      d.check("the timestamp became a jump link") do
        markup.include?('<a href="jump:3723" title="Jump to 01:02:03">1:02:03</a>')
      end
      d.check("the anchor survived") { markup.include?('<a href="https://example.com/a">') }
      d.check("the paragraph became two newlines") { markup.end_with?(".\n\n") }
    end
    EpisodeDescriptionParser.html_to_pango_markup("<ul><li>one</li><li>two</li></ul>")
      .then do |markup|
        d.check("the list became bullets") { markup == "\n    • one\n    • two\n\n" }
      end
  end

  d.step("two found podcasts with the same feed merge into one") do
    d.check("the duplicate is recognised") { RESULTS.first == RESULTS.last }
    RESULTS.first.dup.then do |combined|
      combined.combine(RESULTS.last)
      d.check("the longer description won") { combined.description.start_with?("A longer") }
      d.check("the bigger episode count won") { combined.episode_count == 348 }
    end
  end

  d.step("the discovery page opens") do
    app.window.activate_action("go-to-discovery", nil)
  end

  d.step("and carries a switch per platform") do
    app.main_window.navigation_view.visible_page.then do |page|
      d.check("the discovery page is on top") { page.tag == "discovery" }
      d.check("its title is Add Podcasts") { page.title == "Add Podcasts" }
    end
    d.shot("01-discovery")
  end

  d.step("switching a platform on writes the setting") do
    DiscoveryPage.new(app: app).then do |discovery|
      discovery.build
      discovery.platform_switch("fyyd.de").active = true
      d.check("fyyd is on in the database") { Dbqueries.discovery_settings["fyyd.de"] == true }
      discovery.platform_switch("fyyd.de").active = false
      d.check("and off again") { Dbqueries.discovery_settings["fyyd.de"] == false }
      d.check("both platforms have a switch") do
        Discovery::ALL_PLATFORM_IDS.all? { |id| !discovery.platform_switch(id).nil? }
      end
    end
  end

  d.step("a search with no platform selected refuses before it asks anyone") do
    Discovery::ALL_PLATFORM_IDS.each { |id| Dbqueries.set_discovery_setting(id, false) }
    begin
      Discovery.search("chapo")
      d.check("the search refused") { false }
    rescue Discovery::NoSearchPlatformsSelected
      d.check("the search refused") { true }
    end
  end

  d.step("the search results page lists what was found") do
    DiscoverySearchResults.new(app: app, results: RESULTS).then do |results|
      app.main_window.push_page(results.build)
      d.check("the list is showing") { results.list.visible? }
      d.check("the no-results line is hidden") { !results.no_results_label.visible? }
    end
  end

  d.step("and the rows have their titles, counts and dates") do
    app.main_window.navigation_view.visible_page.then do |page|
      d.check("the results page is on top") { page.tag == "search_results" }
    end
    d.shot("02-results")
  end

  d.step("an empty search shows the no-results line instead") do
    # Pop the first results page first: a real search-again only ever
    # happens after the user has navigated back to the discovery page, so
    # two "search_results"-tagged pages never coexist in the nav stack.
    app.main_window.navigation_view.pop
    DiscoverySearchResults.new(app: app, results: []).then do |results|
      app.main_window.push_page(results.build)
      d.check("the no-results line is up") { results.no_results_label.visible? }
      d.check("the list is gone") { !results.list.visible? }
    end
  end

  d.step("and it settles") do
    d.shot("03-no-results")
  end

  d.step("a found podcast row fills itself in") do
    DiscoveryFoundPodcast.new(app: app, podcast: RESULTS.first).then do |row|
      row.build
      d.check("the title is set") { row.title_label.text == "Corner Späti" }
      d.check("the author is set") { row.author_label.text == "The Späti Boys" }
      d.check("the feed url is set") { row.feed_url_label.text == RESULTS.first.feed }
      d.check("the description is showing") { row.description_label.visible? }
      d.check("the episode count is showing") { row.episode_count_box.visible? }
      d.check("the count reads 348") { row.episode_count_label.text == "348" }
      d.check("the last publication is showing") { row.last_publication_label.visible? }
      d.check("the subscribe button is the visible stack child") do
        row.subscribe_stack.visible_child == row.subscribe_button
      end
    end
  end

  d.step("and a row with nothing extra leaves those lines off") do
    Discovery::FoundPodcast.new(
      feed:             "https://example.com/feed.xml",
      title:            "Bare",
      author:           "Nobody",
      description:      "  ",
      art:              "",
      episode_count:    nil,
      last_publication: nil,
    ).then do |bare|
      DiscoveryFoundPodcast.new(app: app, podcast: bare).then do |row|
        row.build
        d.check("the description stays hidden") { !row.description_label.visible? }
        d.check("the episode count stays hidden") { !row.episode_count_box.visible? }
        d.check("the last publication stays hidden") { !row.last_publication_label.visible? }
      end
    end
  end

  d.step("the thumbnail sizes map onto the display scale the way upstream's do") do
    d.check("unscaled asks for what it wanted") { ThumbnailGenerator.hidpi(64, 1) == 64 }
    d.check("2x takes the next size up") { ThumbnailGenerator.hidpi(64, 2) == 128 }
    d.check("3x takes two sizes up") { ThumbnailGenerator.hidpi(64, 3) == 256 }
    d.check("5x goes to the biggest") { ThumbnailGenerator.hidpi(64, 5) == 512 }
    d.check("there is nothing above 512") { ThumbnailGenerator.hidpi(512, 2).nil? }
  end

  d.step("a cover and its thumbnails land where upstream puts them") do
    Dbqueries.podcasts.then do |shows|
      d.check("there is no subscription to place a cover for") { shows.empty? }
    end
    GdkPixbuf::Pixbuf.new(
      width:     200,
      height:    100,
      has_alpha: false,
    ).then do |source|
      File.join(ROOT, "source.png").then do |path|
        source.fill!(0x3584e4ff)
        source.save(path, "png")
        ThumbnailGenerator::SIZES
          .to_h { |size| [size, File.join(ROOT, "cover-#{size}")] }
          .then { |targets| ThumbnailGenerator.generate(path, targets) }
          .then do |written|
            d.check("all four thumbnails were written") do
              written.length == 4 && written.values.all? { |target| File.exist?(target) }
            end
            d.check("the 64px one is 64 wide and keeps its aspect") do
              GdkPixbuf::Pixbuf.new(file: written[64]).then do |thumb|
                thumb.width == 64 && thumb.height == 32
              end
            end
            d.check("no part file was left behind") do
              Dir.glob(File.join(ROOT, "*.part")).empty?
            end
          end
      end
    end
  end
end
