# frozen_string_literal: true

require "tmpdir"

require "database"
require "models/sync"

# Ported from podcasts-data/src/models/sync/{mod,episode,settings,show}.rs's
# own #[cfg(test)] modules: storing a delta before sync is configured is a
# no-op, storing one after is an upsert keyed the same way upstream's
# ON CONFLICT clauses are, and delete_deltas clears everything at or before
# its cutoff while stamping last_sync.
RSpec.describe Sync do
  around do |example|
    Dir.mktmpdir("gnome-podcasts-spec") do |root|
      Database.connection = Database.new(path: File.join(root, "podcasts.json"))
      example.run
    end
  end

  def configure_sync
    Sync::Settings.store_entry("127.0.0.1", "test_user")
    Sync.delete_deltas(Time.now.utc)
  end

  describe Sync::Settings do
    it "starts unconfigured, and set_active flips the stored flag" do
      expect(Sync::Settings.fetch_entry).to be_nil

      Sync::Settings.store_entry("127.0.0.1", "test_user")
      settings = Sync::Settings.fetch_entry
      expect(settings.active?).to be(true)
      expect(settings.did_first_sync?).to be(false)

      Sync::Settings.set_active(false)
      expect(Sync::Settings.fetch_entry.active?).to be(false)
      Sync::Settings.set_active(true)
      expect(Sync::Settings.fetch_entry.active?).to be(true)
      expect(Sync::Settings.fetch_entry.last_sync_local).to be_nil
    end
  end

  describe Sync::Episode do
    it "records nothing until sync has completed its first run" do
      described_class.store("ep-1", :play, start: 0, position: 15)
      expect(described_class.fetch_all).to be_empty
    end

    it "upserts by (ep_id, action), keeping the newest position" do
      configure_sync

      described_class.store("ep-1", :play, start: 0, position: 15)
      described_class.store("ep-1", :finished)
      described_class.store("ep-1", :downloaded)
      described_class.store("ep-1", :deleted)
      expect(described_class.fetch_all.length).to eq(4)

      described_class.store("ep-1", :play, start: 0, position: 30)
      all = described_class.fetch_all
      expect(all.length).to eq(4)
      expect(all.map(&:action)).to eq([:play, :finished, :downloaded, :deleted])

      play_delta = all.first
      expect(play_delta.position).to eq(30)
      old_remote = Time.now.utc.to_i - 500
      new_remote = Time.now.utc.to_i + 500
      expect(play_delta.should_be_ignored?(old_remote)).to be(false)
      expect(play_delta.should_be_ignored?(new_remote)).to be(true)
    end
  end

  describe Sync::Show do
    it "upserts by uri, the later action winning" do
      configure_sync

      described_class.store_by_uri("https://example.com/feed", :added)
      described_class.store_by_uri("https://example.com/other", :added)
      expect(described_class.fetch_all.length).to eq(2)

      described_class.store_by_uri("https://example.com/feed", :removed)
      described_class.store_by_uri("https://example.com/feed", :moved, new_uri: "https://example.com/other")
      all = described_class.fetch_all
      expect(all.length).to eq(2)
      expect(all.first.action).to eq(:moved)
      expect(all.first.new_uri).to eq("https://example.com/other")
    end

    it "store_multiple_subscriptions upserts every uri as Added" do
      configure_sync

      described_class.store_multiple_subscriptions(["https://example.com/a", "https://example.com/b"])
      all = described_class.fetch_all
      expect(all.length).to eq(2)
      expect(all.map(&:action)).to eq([:added, :added])
    end
  end

  describe ".delete_deltas" do
    it "clears deltas at or before the cutoff and stamps last_sync, keeping newer ones" do
      configure_sync

      Sync::Show.store_by_uri("https://example.com/feed", :added)
      Sync::Episode.store("ep-1", :downloaded)
      expect(Sync::Show.fetch_all.length).to eq(1)
      expect(Sync::Episode.fetch_all.length).to eq(1)

      now = Time.now.utc
      Sync.delete_deltas(now)
      expect(Sync::Show.fetch_all).to be_empty
      expect(Sync::Episode.fetch_all).to be_empty
      expect(Sync::Settings.fetch_entry.last_sync).to eq(now.to_i)
    end
  end
end
