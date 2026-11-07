# frozen_string_literal: true

require_relative "../database"
require_relative "../dbqueries"
require_relative "../errors"

# Sync holds the delta-tracking rows the Nextcloud gpodder sync protocol
# uploads and clears: an Episode or Show action recorded locally, and the one
# Settings row that says whether syncing is configured and when it last ran.
#
# Ported from podcasts-data/src/models/sync/{mod,episode,settings,show}.rs.
# Upstream is three diesel tables (episodes_sync, shows_sync, settings_sync);
# here they are three tables in the port's JSON row store, with the same
# primary keys, the same upsert-on-conflict semantics and the same ignore
# rule for a stale Play action racing a newer one.
#
# Upstream's `Settings::store`/`::fetch`/`::remove` also read and write the
# real password through the desktop keyring (`oo7::Keyring`, Secret
# Service over D-Bus). This port has no secret-storage gem in its dependency
# list — none of the bound gems in the gemspec provide it, and hand-rolling a
# raw `Gio::DBusProxy` Secret Service client is exactly the kind of
# work-around the gem wiring rules warn against writing on spec. So the
# password side of `Settings` is left out of this round: `store_entry`,
# `fetch_entry`, `set_active` and the two timestamp helpers below are the
# full port of everything that does not touch the keyring.
module Sync
  # Ported from sync/episode.rs's Episode.
  #
  # Upstream's `#[diesel(primary_key(ep_id, action))]` on_conflict upsert: a
  # repeated action for the same episode replaces the position and timestamp
  # of the one already queued, rather than adding a second row.
  class Episode
    # Upstream's EpisodeAction enum, encoded as upstream encodes it in the
    # `action` column: a one-letter code.
    ACTIONS = {play: "P", finished: "F", downloaded: "D", deleted: "R"}.freeze
    ACTIONS_BY_CODE = ACTIONS.invert.freeze

    class << self
      # Upstream's Episode::store: records an action to sync later, unless
      # syncing has never completed its first run.
      def store(ep_id, action, start: nil, position: nil)
        if Settings.fetch_entry&.did_first_sync?
          upsert(
            ep_id,
            action,
            start,
            position,
          )
        end
        nil
      end

      # Upstream's Episode::fetch_all.
      def fetch_all
        Database.connection.rows("episodes_sync").map { |row| from_row(row) }
      end

      def from_row(row) = new(row)

      private

        def upsert(ep_id, action, start, position)
          Database.connection.insert(
            "episodes_sync",
            "ep_id"     => ep_id,
            "action"    => ACTIONS.fetch(action),
            "timestamp" => Time.now.utc.to_i,
            "start"     => start,
            "position"  => position,
          )
        end
    end

    def initialize(row)
      @row = row.transform_keys(&:to_s)
    end

    def ep_id = @row["ep_id"]
    def timestamp = @row["timestamp"].to_i
    def start = @row["start"]
    def position = @row["position"]

    # May answer nil if invalid data made it into the store.
    def action = ACTIONS_BY_CODE[@row["action"]]

    # Upstream's should_be_ignored: a Play action is superseded by whatever
    # remote timestamp is newer than it; a Finished action never is.
    def should_be_ignored?(remote_timestamp)
      remote_timestamp > timestamp && action == :play
    end
  end

  # Ported from sync/show.rs's Show.
  class Show
    ACTIONS = {added: "A", removed: "R", moved: "M"}.freeze
    ACTIONS_BY_CODE = ACTIONS.invert.freeze

    class << self
      # Upstream's Show::store(show, action), which looks the uri up from the
      # show's source.
      def store(show, action, new_uri: nil)
        store_by_uri(Dbqueries.source_from_id(show.source_id).uri, action, new_uri: new_uri)
      end

      # Upstream's Show::store_by_uri.
      def store_by_uri(uri, action, new_uri: nil)
        if Settings.fetch_entry&.did_first_sync?
          upsert(uri, action, new_uri)
        end
        nil
      end

      # Upstream's Show::store_multiple_subscriptions: every uri gets an
      # Added action, upserted in one pass.
      def store_multiple_subscriptions(uris)
        if Settings.fetch_entry&.did_first_sync?
          uris.each { |uri| upsert(uri, :added, nil) }
        end
        nil
      end

      def fetch_all
        Database.connection.rows("shows_sync").map { |row| from_row(row) }
      end

      def from_row(row) = new(row)

      private

        def upsert(uri, action, new_uri)
          Database.connection.insert(
            "shows_sync",
            "uri"       => uri,
            "new_uri"   => new_uri,
            "action"    => ACTIONS.fetch(action),
            "timestamp" => Time.now.utc.to_i,
          )
        end
    end

    def initialize(row)
      @row = row.transform_keys(&:to_s)
    end

    def uri = @row["uri"]
    def new_uri = @row["new_uri"]
    def timestamp = @row["timestamp"].to_i

    # May answer nil if invalid data made it into the store, and for a
    # Moved row with no new_uri recorded, matching upstream.
    def action
      code = ACTIONS_BY_CODE[@row["action"]]
      if code == :moved && new_uri.nil?
        nil
      else
        code
      end
    end
  end

  # Ported from sync/settings.rs's Settings: the single row that says which
  # Nextcloud server syncing is configured against, and when it last
  # completed. See the module comment above for what is not ported here.
  class Settings
    class << self
      # Upstream's Settings::fetch_entry.
      def fetch_entry
        Database.connection.rows("settings_sync").first.then { |row| row && new(row) }
      end

      # Upstream's Settings::store_entry: active is always turned on by a
      # fresh (re-)entry, matching the ON CONFLICT clause upstream writes,
      # which never touches `active`.
      def store_entry(server, user)
        existing = fetch_entry
        Database.connection.insert(
          "settings_sync",
          "server"    => server,
          "user"      => user,
          "active"    => existing ? existing.active? : true,
          "last_sync" => existing&.last_sync,
        )
        nil
      end

      # Upstream's Settings::set_active.
      def set_active(active)
        fetch_entry.then do |settings|
          unless settings
            raise Errors::DataError, "no sync settings configured"
          end

          Database.connection.update("settings_sync", settings.id, "active" => active)
        end
        nil
      end
    end

    def initialize(row)
      @row = row.transform_keys(&:to_s)
    end

    def id = @row["id"]
    def server = @row["server"]
    def user = @row["user"]
    def active? = @row["active"] == true
    def last_sync = @row["last_sync"]

    # Upstream's did_first_sync.
    def did_first_sync? = !last_sync.nil?

    # Upstream's last_sync_local: the stored UTC timestamp, in the local zone.
    def last_sync_local
      last_sync.then { |value| value && Time.at(value.to_i).localtime }
    end
  end

  class << self
    # Upstream's sync::delete_deltas: clears every delta at or before `now`
    # and stamps `last_sync` with it, in one pass so a sync that uploaded a
    # consistent snapshot never loses track of what it covered.
    def delete_deltas(now = Time.now.utc)
      cutoff = now.to_i
      Database.connection.delete_where("episodes_sync") { |row| row["timestamp"].to_i <= cutoff }
      Database.connection.delete_where("shows_sync") { |row| row["timestamp"].to_i <= cutoff }
      stamp_last_sync(cutoff)
      nil
    end

    private

      def stamp_last_sync(cutoff)
        Settings.fetch_entry.then do |settings|
          if settings
            Database.connection.update("settings_sync", settings.id, "last_sync" => cutoff)
          end
        end
      end
  end
end
