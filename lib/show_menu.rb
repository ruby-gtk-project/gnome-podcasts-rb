# frozen_string_literal: true

require "gtk4"

# ShowMenu is the show page's menu: the feed's website, mark everything
# played, and unsubscribe.
#
# Ported from podcasts-gtk/src/widgets/show_menu.rs and
# podcasts-gtk/resources/gtk/show_menu.ui: two sections, three actions in a
# "show" action group that upstream inserts on the window, and the two toasts
# with an "Undo" button that upstream builds here —
# "Marked all episodes as listened" and "Unsubscribed from {show}" — which
# only commit once the toast goes away undismissed.
#
# podcasts-gtk/resources/gtk/secondary_menu.ui is not ported: nothing in
# upstream builds it any more, its items having moved into this menu and the
# window's.
class ShowMenu
  WEBSITE_SECTION = [
    ["Open Website", "show.open-website"],
    ["Mark All as Played", "show.mark-played"],
  ].freeze

  UNSUBSCRIBE_SECTION = [
    ["Unsubscribe", "show.unsubscribe"],
  ].freeze

  def initialize(app:, show:, widget:)
    @app = app
    @show = show
    @widget = widget
  end

  attr_reader :app, :show, :widget

  # Builds the actions and answers self; the caller hands `menu` to its menu
  # button and `group` to the window.
  def build
    tap do
      add_action("open-website") { app.open_website(show) }
      add_action("mark-played") { mark_played }
      add_action("unsubscribe") { |action| unsubscribe(action) }
    end
  end

  def menu
    @menu ||= Gio::Menu.new.tap do |model|
      model.append_section(nil, section(WEBSITE_SECTION))
      model.append_section(nil, section(UNSUBSCRIBE_SECTION))
    end
  end

  def group = @group ||= Gio::SimpleActionGroup.new

  private

    # Upstream's connect_played: the rows go dim right away and the database
    # is only written once the toast has had its chance to undo.
    def mark_played
      widget.mark_all_played
      app.mark_all_played_notification(show)
    end

    # Upstream's connect_unsub: the show disappears from the views at once and
    # the rows and files go only when the toast expires.
    def unsubscribe(action)
      action.enabled = false
      app.remove_show(show)
      action.enabled = true
    end

    def add_action(name, &block)
      Gio::SimpleAction.new(name).tap do |action|
        action.signal_connect("activate") { block.call(action) }
        group.add_action(action)
      end
    end

    def section(items)
      Gio::Menu.new.tap do |model|
        items.each { |label, action_name| model.append(label, action_name) }
      end
    end
end
