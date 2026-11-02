# frozen_string_literal: true

require "gtk4"
require_relative "feed_manager"
require_relative "opml"

# OpmlDialogs are the two file dialogs behind "Import Shows" and
# "Export Shows".
#
# Ported from the import and export halves of podcasts-gtk/src/utils.rs
# (`on_import_clicked` and `on_export_clicked`): the same OPML file filter, the
# same titles and accept labels, the same suggested export name, an import that
# indexes the urls and then schedules a refresh of them, and an export that
# writes every subscription out.
#
# Upstream awaits the dialog's future; the Ruby bindings take the Gio async
# callback instead, so the work happens in the callback.
class OpmlDialogs
  FILTER_NAME = "OPML file"
  MIME_TYPES = ["application/xml", "text/xml", "text/x-opml"].freeze
  # Translators: This is the string of the suggested name for the exported opml file
  EXPORT_NAME = "gnome-podcasts-exported-shows"
  EXPORT_TITLE = "GNOME Podcasts Subscriptions"

  def initialize(app:, window:)
    @app = app
    @window = window
  end

  attr_reader :app, :window

  def import
    import_dialog.open(window, nil) do |dialog, result|
      path_from(dialog, result, :open_finish).then do |path|
        if path
          import_from(path)
        end
      end
    end
  end

  def export
    export_dialog.save(window, nil) do |dialog, result|
      path_from(dialog, result, :save_finish).then do |path|
        if path
          export_to(path)
        end
      end
    end
  end

  def import_dialog
    @import_dialog ||= Gtk::FileDialog.new.tap do |dialog|
      dialog.title = "Select the file from which to you want to import shows."
      dialog.accept_label = "_Import"
      dialog.filters = filters
    end
  end

  def export_dialog
    @export_dialog ||= Gtk::FileDialog.new.tap do |dialog|
      # Translators: Show as a noun, meaning Podcast-Shows.
      dialog.title = "Export shows to…"
      dialog.accept_label = "_Export"
      dialog.initial_name = "#{EXPORT_NAME}.opml"
      dialog.filters = filters
    end
  end

  def filters
    @filters ||= Gio::ListStore.new(Gtk::FileFilter).tap do |store|
      store.append(file_filter)
    end
  end

  def file_filter
    @file_filter ||= Gtk::FileFilter.new.tap do |filter|
      filter.name = FILTER_NAME
      MIME_TYPES.each { |mime| filter.add_mime_type(mime) }
    end
  end

  private

    # A cancelled dialog raises rather than answering nil, and that is not an
    # error worth a toast.
    def path_from(dialog, result, finish)
      dialog.public_send(finish, result)&.path
    rescue StandardError
      nil
    end

    def import_from(path)
      Opml.import_from_file(path).then do |sources|
        FeedManager.schedule_refresh(sources)
        app.watch_refresh
      end
    rescue StandardError => e
      app.error_notification("Failed to parse the imported file #{e.message}")
    end

    def export_to(path)
      Opml.export_from_db(path, EXPORT_TITLE)
    rescue StandardError => e
      warn "Failed to export podcasts: #{e.message}"
      app.error_notification("Failed to export podcasts")
    end
end
