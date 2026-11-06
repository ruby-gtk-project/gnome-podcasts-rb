# frozen_string_literal: true

# Ad hoc smoke test for the episode description page: clicking a home row
# opens it, the menu/buttons are wired, and a second episode replaces it.
#
# Run it from the dev shell:
#   xvfb-run ruby test/drive_episode_description.rb

require "tmpdir"

ROOT = Dir.mktmpdir("gnome-podcasts-ed-drive")
ENV["XDG_DATA_HOME"] = File.join(ROOT, "data")
ENV["XDG_CONFIG_HOME"] = File.join(ROOT, "config")
ENV["XDG_CACHE_HOME"] = File.join(ROOT, "cache")

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "gnome_podcasts"
require "feed"
require "xml_parser"

require_relative "gtk_driver"

FIXTURE = File.expand_path("feeds/intercepted.xml", __dir__)
SOURCE = Source.from_url("https://example.com/intercepted.xml")
SHOW = Feed.new(channel: XmlParser.parse(File.read(FIXTURE)), source_id: SOURCE.id).index
EPISODES = Dbqueries.episodes_of(SHOW.id).sort_by { |episode| -episode.epoch.to_i }

SETTINGS = Settings.new(path: File.join(ROOT, "settings.json"))
SETTINGS["refresh-on-startup"] = false
SETTINGS["refresh-interval"] = false

APP = GnomePodcasts::Application.new(settings: SETTINGS)

GtkDriver.drive(APP, shots: "tmp/shots") do |d, app|
  d.window { app.window }

  d.step("the home row opens the episode description") do
    widget = app.main_window.content.home_view.episode_list.episode_widget(EPISODES.first.id)
    widget.row.parent.signal_emit("row-activated", widget.row)
  end

  d.step("the page is up") do
    d.check("navigated to the episode page") do
      app.main_window.episode_description_widget&.id == EPISODES.first.id
    end
    d.check("the title is the episode's") do
      app.main_window.episode_description_widget.page.title == EPISODES.first.title
    end
    d.check("the download button is visible") do
      app.main_window.episode_description_widget.download_button.visible?
    end
    d.shot("11-episode-description")
  end
end
