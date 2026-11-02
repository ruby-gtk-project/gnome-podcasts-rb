# frozen_string_literal: true

require "gtk4"
require "adwaita"

require_relative "../data_utils"
require_relative "../dbqueries"
require_relative "../download_manager"
require_relative "../feed_manager"
require_relative "../icons"
require_relative "../main_window"
require_relative "../settings"
require_relative "../shortcuts_dialog"
require_relative "../show_widget"
require_relative "../style"
require_relative "../utils"

module GnomePodcasts
  # Application is the app itself: its actions, its accelerators, and the
  # dispatcher every widget sends its work through.
  #
  # Ported from podcasts-gtk/src/app.rs. Upstream's widgets hold a
  # `Sender<Action>` and push variants of the `Action` enum down a channel that
  # `do_action` drains on the main loop; the port has no channel, so the
  # widgets hold this object and call the method named after the action. The
  # set of methods below is that enum, minus the variants that belong to
  # components the port has not reached yet (the player, the chapters, the
  # episode description page, the discovery pages and the Nextcloud sync).
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  class Application
    APP_ID = "org.rubygtkproject.GnomePodcasts"
    DOWNLOAD_WATCH_INTERVAL = 500

    # Upstream's setup_accels, minus the player's and the discovery page's.
    ACCELS = {
      "app.quit"        => ["<Control>q"],
      "app.shortcuts"   => ["<Control>question"],
      "win.open-search" => ["<Control>f"],
      "win.refresh"     => ["<Control>r", "F5"],
      "win.go-to-home"  => ["F1", "<Alt>1"],
      "win.go-to-shows" => ["F2", "<Alt>2"],
      "win.go-to-queue" => ["F3", "<Alt>3"],
      "win.import"      => ["<Control>o"],
      "win.export"      => ["<Control>e"],
      "window.close"    => ["<Control>w"],
    }.freeze

    def initialize(settings: nil, present: true)
      @settings = settings || Settings.new
      @present = present
    end

    attr_reader :settings

    def build
      app.tap do
        app.signal_connect("startup") { on_startup }

        app.signal_connect("activate") do
          Style.load
          Icons.load

          main_window.build

          install_actions
          install_accels

          if @present
            main_window.window.present
          end
        end
      end
    end

    def run = app.run([])

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and only the window is Adwaita.
    def app = @app ||= Gtk::Application.new(APP_ID, :default_flags)
    def main_window = @main_window ||= MainWindow.new(app: self, settings: settings)
    def window = main_window.window

    # Actions, upstream's Action enum
    # ---------------------------------------------------------------

    # Upstream's win.refresh / FEED_MANAGER.schedule_full_refresh.
    def refresh_feeds
      if FeedManager.schedule_full_refresh
        main_window.watch_refresh
      end
    end

    def watch_refresh
      main_window.watch_refresh
    end

    # Upstream's Action::RefreshAllViews.
    def refresh_all_views
      main_window.content.update
    end

    # Upstream's Action::RefreshEpisodesView / RefreshShowsView.
    def refresh_episodes_view
      main_window.content.update_home
    end

    def refresh_shows_view
      main_window.content.update_shows
    end

    # Upstream's Action::RefreshEpisode: every page that shows this episode
    # hears about it.
    def refresh_episode(episode_id)
      Dbqueries.episode_from_id(episode_id).then do |episode|
        main_window.content.update_home_episode(episode)
        main_window.content.update_queue_episode(episode)
        if main_window.show_widget
          main_window.show_widget.update_episode(episode)
        end
      end
    rescue KeyError => e
      warn "failed to fetch episode for refresh: #{e.message}"
    end

    # Upstream's Action::RefreshWidgetIfSame.
    def refresh_show_if_same(show_id)
      if main_window.show_widget && main_window.show_widget.show_id == show_id
        main_window.show_widget.reload
      end
    end

    # Upstream's Action::ReplaceWidget plus GoToShow.
    def go_to_show(show)
      main_window.replace_show_widget(ShowWidget.new(app: self, show: show), show.title)
      main_window.go_to_show_widget
    end

    def go_to_show_by_id(show_id)
      go_to_show(Dbqueries.podcast_from_id(show_id))
    end

    # Upstream's Action::MarkAsPlayed.
    def mark_as_played(played, episode_id)
      Dbqueries.episode_from_id(episode_id).then do |episode|
        if played
          episode.set_played_now
        else
          episode.set_unplayed
        end
        refresh_episode(episode_id)
      end
    end

    # Upstream's Action::AddToQueue.
    def add_to_queue(episode_id)
      Dbqueries.add_episode_to_queue(episode_id)
      main_window.content.update_queue
      refresh_episode(episode_id)
    end

    # Upstream's Action::RemoveFromQueue.
    def remove_from_queue(episode_id)
      if Dbqueries.queued?(episode_id)
        Dbqueries.remove_queue_item(Dbqueries.queue_item(episode_id))
        main_window.content.update_queue_after_removal(episode_id)
        refresh_episode(episode_id)
      end
    end

    # Upstream's Action::MoveUpInQueue / MoveDownInQueue.
    def move_up_in_queue(episode_id)
      Dbqueries.move_episode_up_in_queue(episode_id)
      after_queue_move(episode_id)
    end

    def move_down_in_queue(episode_id)
      Dbqueries.move_episode_down_in_queue(episode_id)
      after_queue_move(episode_id)
    end

    # Upstream's Action::MoveToPositionInQueue, which the rows' drag and drop
    # sends.
    def move_to_position_in_queue(episode_id, target_episode_id, bottom_target)
      Dbqueries.move_episode_to_position_in_queue(episode_id, target_episode_id, bottom_target)
      after_queue_move(episode_id)
    end

    # Upstream's on_download_clicked: start the download and let the views
    # pick the new state up.
    def download_episode(episode_id)
      DownloadManager.add(episode_id)
      watch_downloads
      refresh_episode(episode_id)
    end

    # Upstream's episode.delete action: the file goes, the row stays.
    def delete_episode_download(episode_id)
      Dbqueries.episode_from_id(episode_id).then do |episode|
        DataUtils.delete_local_content(episode)
        remove_from_queue(episode_id)
        refresh_episode(episode_id)
      end
    end

    # Upstream's Action::CopyUrl plus CopiedUrlNotification.
    def copy_url(episode_id)
      Dbqueries.episode_from_id(episode_id).then do |episode|
        if episode.uri
          Gdk::Display.default.clipboard.set(episode.uri)
          toast("Copied URL to clipboard!")
        end
      end
    end

    # Upstream's show.open-website action.
    def open_website(show)
      Gtk::UriLauncher.new(show.link).launch(window, nil) { |launcher, result| launched(launcher, result) }
    end

    # Upstream's mark_all_notif: the toast commits the change when it goes
    # away, and "Undo" cancels it.
    def mark_all_played_notification(show)
      undoable_toast("Marked all episodes as listened") do
        Dbqueries.update_none_to_played_now(show)
        refresh_show_if_same(show.id)
        refresh_episodes_view
      end
    end

    # Upstream's Action::RemoveShow plus remove_show_notif: the show is hidden
    # from the views at once, and deleted for good when the toast expires.
    def remove_show(show)
      main_window.pop_show_widget
      Utils.ignore_show(show.id)
      refresh_all_views

      undoable_toast("Unsubscribed from #{show.title}") do
        Utils.unignore_show(show.id)
        DataUtils.delete_show(show)
        refresh_all_views
      end
    end

    # Upstream's Action::ErrorNotification.
    def error_notification(text)
      warn "An error notification was triggered: #{text}"
      toast(text)
    end

    def toast(text)
      main_window.add_toast(Adwaita::Toast.new(text))
    end

    # Upstream's Action::EmptyState / PopulatedState: with nothing subscribed
    # the switchers and the filters go insensitive and the empty page takes
    # the stack over.
    def empty_state
      window.lookup_action("refresh")&.enabled = false
      main_window.top_switcher.sensitive = false
      main_window.bottom_switcher_bar.sensitive = false
      main_window.filter_stack.visible = false
      main_window.content.switch_to_empty_views
    end

    def populated_state
      window.lookup_action("refresh")&.enabled = true
      main_window.top_switcher.sensitive = true
      main_window.bottom_switcher_bar.sensitive = true
      main_window.filter_stack.visible = true
      main_window.content.switch_to_populated
    end

    def shortcuts_dialog = @shortcuts_dialog ||= ShortcutsDialog.new

    private

      # Upstream's startup: garbage collect the episodes whose cleanup age has
      # passed before anything is shown.
      def on_startup
        DataUtils.checkup(settings.cleanup_date)
      rescue StandardError => e
        warn "Check up failed: #{e.message}"
      end

      # Upstream's setup_gactions, minus the actions whose destinations the
      # port has not reached yet.
      def install_actions
        {
          "quit"      => -> { app.quit },
          "shortcuts" => -> { shortcuts_dialog.build.present(window) },
        }.each do |name, handler|
          Gio::SimpleAction.new(name).tap do |action|
            action.signal_connect("activate") { handler.call }
            app.add_action(action)
          end
        end
      end

      def install_accels
        ACCELS.each { |name, accels| app.set_accels_for_action(name, accels) }
      end

      def after_queue_move(episode_id)
        main_window.content.update_queue_after_move(
          episode_id,
          Dbqueries.queue_index_after_move(episode_id),
        )
      end

      # A toast that performs its work unless its "Undo" button is pressed
      # first, which is the shape of both of upstream's undoable actions.
      def undoable_toast(text, &block)
        Adwaita::Toast.new(text).tap do |toast|
          undone = []
          toast.button_label = "Undo"
          toast.signal_connect("button-clicked") { undone << true }
          toast.signal_connect("dismissed") do
            if undone.empty?
              block.call
            end
          end
          main_window.add_toast(toast)
        end
      end

      # The downloads report their errors from their own threads, so the main
      # loop collects them while any download is running.
      def watch_downloads
        unless @watching_downloads
          @watching_downloads = true
          GLib::Timeout.add(DOWNLOAD_WATCH_INTERVAL) { download_tick }
        end
      end

      def download_tick
        DownloadManager.take_errors.each { |message| error_notification(message) }
        DownloadManager.active_count.positive?.tap do |busy|
          unless busy
            @watching_downloads = false
          end
        end
      end

      def launched(launcher, result)
        launcher.launch_finish(result)
      rescue StandardError => e
        warn "Failed to open the website: #{e.message}"
      end
  end
end
