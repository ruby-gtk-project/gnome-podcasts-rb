# frozen_string_literal: true

require "json"
require "fileutils"

# Database is the port's row store.
#
# Ported from podcasts-data/src/database.rs together with the table layout in
# podcasts-data/src/schema.rs and the migrations under
# podcasts-data/migrations/.
#
# Upstream is diesel on SQLite: a connection pool, a migration runner and
# `reset_db` for the tests. Nothing in the port's runtime closure speaks SQLite
# (nix/Gemfile pins only gtk4 and adwaita), so the same tables, columns,
# primary keys and uniqueness rules are kept in a single JSON document under
# XDG_DATA_HOME instead. Every table that upstream gives an autoincrementing
# integer primary key gets one here too, so the ids in the UI's action targets
# mean the same thing they do upstream.
class Database
  TABLES = %w[source shows episodes queue discovery_settings episodes_sync shows_sync settings_sync].freeze

  # Upstream's unique indexes, from migrations/*/up.sql. A write that would
  # duplicate one of these tuples replaces the existing row, which is what
  # diesel's `INSERT OR REPLACE`-shaped index/update pairs do.
  #
  # episodes_sync, shows_sync and settings_sync are the delta-tracking tables
  # podcasts-data/src/models/sync/{episode,show,settings}.rs upsert into, with
  # the same primary keys: (ep_id, action), uri, and server (settings_sync
  # holds a single row, same as upstream keeps a single row in it).
  UNIQUE_KEYS = {
    "source"             => [%w[uri]],
    "shows"              => [%w[source_id]],
    "episodes"           => [%w[show_id guid], %w[show_id title]],
    "queue"              => [%w[episode_id], %w[position]],
    "discovery_settings" => [%w[platform_id]],
    "episodes_sync"      => [%w[ep_id action]],
    "shows_sync"         => [%w[uri]],
    "settings_sync"      => [%w[server]],
  }.freeze

  class << self
    # The process-wide store, the equivalent of upstream's lazily initialized
    # connection pool.
    def connection = @connection ||= new

    # Points the store at another file; the specs use it, and so does
    # `reset_db`.
    def connection=(database)
      @connection = database
    end

    def reset_db(path: nil)
      self.connection = new(path: path)
      connection.tap { |db| db.clear }
    end
  end

  def initialize(path: nil)
    @path = path || default_path
    @data = read
  end

  attr_reader :path

  def rows(table) = @data.fetch(table, [])

  def clear
    @data = empty_data
    write
  end

  # Inserts a row and returns it with its assigned id. A row that collides with
  # one of the table's unique keys replaces that row rather than duplicating
  # it.
  def insert(table, attributes)
    attributes.transform_keys(&:to_s).then do |attrs|
      existing(table, attrs).then do |old|
        if old
          update(table, old["id"], attrs)
        else
          attrs.merge("id" => next_id(table)).tap do |row|
            @data[table] << row
            write
          end
        end
      end
    end
  end

  def update(table, id, attributes)
    find(table, id).then do |row|
      unless row
        raise KeyError, "no #{table} row with id #{id}"
      end

      row.merge!(attributes.transform_keys(&:to_s)).tap { write }
    end
  end

  def find(table, id) = rows(table).find { |row| row["id"] == id }

  def delete(table, id)
    rows(table).reject! { |row| row["id"] == id }.then do |deleted|
      write
      !deleted.nil?
    end
  end

  # Deletes every row the block accepts and answers how many went away.
  def delete_where(table)
    rows(table).length.then do |before|
      @data[table] = rows(table).reject { |row| yield(row) }
      write
      before - rows(table).length
    end
  end

  private

    def default_path
      File.join(
        ENV.fetch("XDG_DATA_HOME", File.expand_path("~/.local/share")),
        "gnome-podcasts-rb",
        "podcasts.json",
      )
    end

    def empty_data = TABLES.to_h { |table| [table, []] }

    def read
      File.exist?(@path).then do |exists|
        if exists
          empty_data.merge(JSON.parse(File.read(@path)))
        else
          empty_data
        end
      end
    rescue JSON::ParserError => e
      warn "Error parsing #{@path}: #{e.message}"
      empty_data
    end

    def write
      FileUtils.mkdir_p(File.dirname(@path))
      File.write("#{@path}.tmp", JSON.pretty_generate(@data))
      File.rename("#{@path}.tmp", @path)
    end

    def next_id(table)
      rows(table).map { |row| row["id"].to_i }.max.to_i + 1
    end

    def existing(table, attrs)
      UNIQUE_KEYS.fetch(table, []).filter_map do |columns|
        if columns.all? { |column| !attrs[column].nil? }
          rows(table).find { |row| columns.all? { |column| row[column] == attrs[column] } }
        end
      end.first
    end
end
