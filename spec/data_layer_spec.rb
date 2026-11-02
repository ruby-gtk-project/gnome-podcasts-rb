# frozen_string_literal: true

require "tmpdir"

require "database"
require "dbqueries"
require "feed"
require "opml"
require "parser"
require "settings"
require "utils"
require "xml_parser"

# The data layer has no widgets in it, so it is covered here rather than in
# test/drive_main_window.rb: parsing a feed, indexing it, the queries the views
# ask, and the OPML round trip.
RSpec.describe "the data layer" do
  let(:fixture) { File.expand_path("../test/feeds/intercepted.xml", __dir__) }
  let(:opml_fixture) { File.expand_path("../test/feeds/export_test.opml", __dir__) }

  around do |example|
    Dir.mktmpdir("gnome-podcasts-spec") do |root|
      @root = root
      Database.connection = Database.new(path: File.join(root, "podcasts.json"))
      example.run
    end
  end

  def index_fixture
    Source.from_url("https://example.com/intercepted.xml").then do |source|
      Feed.new(
        channel:   XmlParser.parse(File.read(fixture)),
        source_id: source.id,
      ).index
    end
  end

  describe XmlParser do
    it "reads elements, attributes, namespaces and CDATA" do
      described_class.parse(<<~XML).then do |root|
        <?xml version="1.0"?>
        <rss xmlns:itunes="http://itunes.com">
          <channel>
            <title>A &amp; B</title>
            <itunes:image href="https://example.com/cover.png"/>
            <item><description><![CDATA[<b>hi</b>]]></description></item>
          </channel>
        </rss>
      XML
        channel = root.element("channel")
        expect(root.name).to eq("rss")
        expect(channel.text_of("title")).to eq("A & B")
        expect(channel.element("itunes:image").attribute("href")).to eq("https://example.com/cover.png")
        expect(channel.element("item").text_of("description")).to eq("<b>hi</b>")
      end
    end
  end

  describe Parser do
    it "reads the iTunes duration in every shape the spec allows" do
      expect(described_class.itunes_duration("3370")).to eq(3370)
      expect(described_class.itunes_duration("6:10")).to eq(370)
      expect(described_class.itunes_duration("56:10")).to eq(3370)
      expect(described_class.itunes_duration("1:56:10")).to eq(6970)
      expect(described_class.itunes_duration("01:56:10")).to eq(6970)
      expect(described_class.itunes_duration("")).to be_nil
    end
  end

  describe Feed do
    it "indexes the channel and its items" do
      show = index_fixture

      expect(show.title).to eq("Intercepted with Jeremy Scahill")
      expect(show.link).to eq("https://theintercept.com/podcasts")
      expect(show.image_uri).to start_with("http://static.megaphone.fm/")
      expect(Dbqueries.episodes_of(show.id).length).to eq(43)
    end

    it "reads the parts of an episode the rows carry" do
      show = index_fixture
      episode = Dbqueries.episodes_of(show.id).max_by { |ep| ep.epoch.to_i }

      expect(episode.title).to eq("White Mirror")
      expect(episode.uri).to start_with("http://traffic.megaphone.fm/")
      expect(episode.duration).to eq(6409)
      expect(episode.length).to eq(102_550_465)
      expect(episode.guid).to eq("3660ad94-fb38-11e7-847d-436a066985fa")
      expect(episode.epoch.utc.to_s).to eq("2018-01-17 11:00:00 UTC")
      expect(episode.description).not_to be_empty
    end

    it "indexes the same feed twice without duplicating anything" do
      show = index_fixture
      Feed.new(
        channel:   XmlParser.parse(File.read(fixture)),
        source_id: show.source_id,
      ).index

      expect(Dbqueries.podcasts.length).to eq(1)
      expect(Dbqueries.episodes_of(show.id).length).to eq(43)
    end

    it "keeps the columns the user owns when a feed is re-indexed" do
      show = index_fixture
      episode = Dbqueries.episodes_of(show.id).first
      episode.set_played_now
      episode.local_uri = "/tmp/an-episode.mp3"

      Feed.new(
        channel:   XmlParser.parse(File.read(fixture)),
        source_id: show.source_id,
      ).index

      Dbqueries.episode_from_id(episode.id).then do |reloaded|
        expect(reloaded).to be_played
        expect(reloaded.local_uri).to eq("/tmp/an-episode.mp3")
      end
    end
  end

  describe Dbqueries do
    it "filters episodes by played state and search text" do
      show = index_fixture
      episodes = Dbqueries.episodes_of(show.id)
      episodes.first.set_played_now

      played = described_class::EpisodeFilter.new(played: true)
      unplayed = described_class::EpisodeFilter.new(played: false)
      searched = described_class::EpisodeFilter.new(search: "mirror")

      expect(played.apply(episodes).length).to eq(1)
      expect(unplayed.apply(episodes).length).to eq(42)
      expect(searched.apply(episodes).map(&:title)).to include("White Mirror")
    end

    it "orders the home page newest first, and oldest first when reversed" do
      show = index_fixture
      episodes = Dbqueries.episodes_of(show.id)

      newest = described_class::EpisodeFilter.new.apply(episodes)
      oldest = described_class::EpisodeFilter.new(reverse_order: true).apply(episodes)

      expect(newest.first.epoch).to be > newest.last.epoch
      expect(oldest.first.epoch).to be < oldest.last.epoch
    end

    it "filters shows by completion, downloads and text" do
      show = index_fixture

      expect(described_class.podcasts_filter([], described_class::ShowFilter.new).length).to eq(1)
      expect(
        described_class.podcasts_filter([], described_class::ShowFilter.new(completed: true)),
      ).to be_empty
      expect(
        described_class.podcasts_filter([], described_class::ShowFilter.new(any_downloaded: true)),
      ).to be_empty
      expect(
        described_class
          .podcasts_filter([], described_class::ShowFilter.new(title_or_description: "intercept"))
          .map(&:id),
      ).to eq([show.id])
    end

    it "hides the shows the undo toast is still holding" do
      show = index_fixture

      expect(described_class.episodes_populated?([])).to be(true)
      expect(described_class.episodes_populated?([show.id])).to be(false)
      expect(described_class.podcasts_filter([show.id], described_class::ShowFilter.new)).to be_empty
    end

    it "queues episodes, reorders them and takes them out again" do
      show = index_fixture
      first, second, third = Dbqueries.episodes_of(show.id).first(3)

      [first, second, third].each { |episode| described_class.add_episode_to_queue(episode.id) }
      expect(described_class.queue.map(&:episode_id)).to eq([first.id, second.id, third.id])
      expect(described_class).to be_first_position_in_queue(first.id)
      expect(described_class).to be_last_position_in_queue(third.id)

      described_class.move_episode_down_in_queue(first.id)
      expect(described_class.queue.map(&:episode_id)).to eq([second.id, first.id, third.id])

      described_class.move_episode_up_in_queue(third.id)
      expect(described_class.queue.map(&:episode_id)).to eq([second.id, third.id, first.id])

      described_class.move_episode_to_position_in_queue(first.id, second.id, false)
      expect(described_class.queue.map(&:episode_id)).to eq([first.id, second.id, third.id])
      expect(described_class.queue_index_after_move(first.id)).to eq(0)

      described_class.remove_queue_item(described_class.queue_item(second.id))
      expect(described_class.queue.map(&:episode_id)).to eq([first.id, third.id])
    end

    it "marks every unplayed episode of a show played" do
      show = index_fixture

      expect(described_class.update_none_to_played_now(show)).to eq(43)
      expect(described_class.pd_unplayed_episodes(show)).to be_empty
    end

    it "removes a feed with its episodes and queue rows" do
      show = index_fixture
      described_class.add_episode_to_queue(Dbqueries.episodes_of(show.id).first.id)

      described_class.remove_feed(show)

      expect(described_class.podcasts).to be_empty
      expect(described_class.episodes).to be_empty
      expect(described_class.queue).to be_empty
      expect(described_class.source_exists?("https://example.com/intercepted.xml")).to be(false)
    end
  end

  describe Opml do
    it "reads the feed urls out of an OPML file" do
      described_class.extract_sources(File.read(opml_fixture)).then do |outlines|
        expect(outlines.length).to eq(6)
        expect(outlines.map(&:url)).to all(start_with("https://web.archive.org/"))
      end
    end

    it "round-trips the subscriptions through an export" do
      index_fixture
      path = File.join(@root, "export.opml")

      described_class.export_from_db(path, "GNOME Podcasts Subscriptions")

      expect(described_class.extract_sources(File.read(path)).map(&:url))
        .to eq(["https://example.com/intercepted.xml"])
      expect(File.read(path)).to include("Intercepted with Jeremy Scahill")
    end
  end

  describe Settings do
    it "keeps the schema's defaults, ranges and derived durations" do
      settings = Settings.new(path: File.join(@root, "settings.json"))

      expect(settings["persist-window-geometry-width"]).to eq(860)
      expect(settings.refresh_interval_seconds).to eq(3600)
      expect(settings.cleanup_date).to be < Time.now.utc

      settings["refresh-interval-time"] = 300
      expect(settings["refresh-interval-time"]).to eq(100)

      expect(Settings.new(path: settings.path)["refresh-interval-time"]).to eq(100)
    end
  end

  describe Utils do
    it "formats the strings the episode rows print" do
      expect(described_class.format_duration(0)).to eq("-")
      expect(described_class.format_duration(125)).to eq("02:05")
      expect(described_class.format_duration(3725)).to eq("1:02:05")
      expect(described_class.format_minutes(6409)).to eq("106 min")
      expect(described_class.format_size(102_550_465)).to eq("98 MiB")
      expect(described_class.format_size(0)).to be_nil
      expect(described_class.relative_time(30)).to eq("Just now")
      expect(described_class.relative_time(3 * 60 * 60)).to eq("3 hours ago")
    end
  end
end
