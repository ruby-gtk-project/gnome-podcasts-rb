# frozen_string_literal: true

require "adwaita"

# ShortcutsDialog lists the keyboard shortcuts.
#
# Ported from podcasts-gtk/resources/gtk/shortcuts-dialog.ui: the same three
# sections — Navigation, Player, General — in the same order. Upstream's items
# name an action and let GTK look the accelerator up; the Ruby bindings want
# the accelerator itself, so each item carries the accelerator the application
# binds to that action in `setup_accels`.
#
# The items whose action the port has not reached yet are left out rather than
# listed as shortcuts that do nothing: the Player section arrives with
# lib/player.rb, and "Go To Discovery Page" with lib/discovery_page.rb.
class ShortcutsDialog < Adwaita::ShortcutsDialog
  SECTIONS = {
    "Navigation" => [
      ["Go to Home Page", "F1"],
      # Translators: Shows as a Noun
      ["Go to Shows Page", "F2"],
      # Translators: Queue as a Noun
      ["Go to Queue Page", "F3"],
    ],
    "General"    => [
      ["Check for new episodes", "<Control>r"],
      ["Import Subscriptions", "<Control>o"],
      ["Export Subscriptions", "<Control>e"],
      ["Search", "<Control>f"],
      ["Quit the application", "<Control>q"],
    ],
  }.freeze

  def initialize
    super()
    self.title = "Keyboard Shortcuts"
  end

  def build
    tap do |dialog|
      SECTIONS.each { |title, items| dialog.add(section(title, items)) }
    end
  end

  private

    def section(title, items)
      Adwaita::ShortcutsSection.new.tap do |section|
        section.title = title
        items.each { |label, accelerator| section.add(item(label, accelerator)) }
      end
    end

    # Positional, not keyword, arguments — even though the error a no-argument
    # `new` raises advertises the signatures as "title: utf8,
    # accelerator: utf8".
    def item(label, accelerator) = Adwaita::ShortcutsItem.new(label, accelerator)
end
