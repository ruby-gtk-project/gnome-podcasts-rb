# frozen_string_literal: true

require "gtk4"

# MainMenu is the hamburger menu in the header bar.
#
# Ported from the `<menu id="menu">` of podcasts-gtk/resources/gtk/window.ui:
# two sections, the first with the feed actions, the second with the shortcuts
# window and the about dialog. The action names are the window's and the
# application's, exactly as upstream names them, so the same menu item drives
# the same action.
class MainMenu
  FEED_SECTION = [
    ["_Check for New Episodes", "win.refresh"],
    # Translators: Show as a noun, meaning Podcast-Shows.
    ["_Import Shows", "win.import"],
    # Translators: Show as a noun, meaning Podcast-Shows.
    ["_Export Shows", "win.export"],
  ].freeze

  APP_SECTION = [
    ["_Keyboard Shortcuts", "app.shortcuts"],
    ["_About Podcasts", "win.about"],
  ].freeze

  def build
    menu.tap do |model|
      model.append_section(nil, section(FEED_SECTION))
      model.append_section(nil, section(APP_SECTION))
    end
  end

  def menu = @menu ||= Gio::Menu.new

  private

    def section(items)
      Gio::Menu.new.tap do |model|
        items.each { |label, action| model.append(label, action) }
      end
    end
end
