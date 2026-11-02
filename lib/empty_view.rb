# frozen_string_literal: true

require "adwaita"

# EmptyView is what the content stack shows when nothing is subscribed.
#
# Ported from podcasts-gtk/src/widgets/empty_view.rs and
# podcasts-gtk/resources/gtk/empty_view.ui: a status page titled "Get Some
# Shows" carrying the app icon, over two hint rows that point at the two ways
# in — a feed url, or an import from another device.
class EmptyView
  APP_ICON = "org.rubygtkproject.GnomePodcasts"

  HINTS = [
    # Translators: Shows as a noun, meaning Podcast-Shows.
    ["list-add-symbolic", "Add new shows via feed URL"],
    # Translators: Shows as a noun, meaning Podcast-Shows.
    ["open-menu-symbolic", "Import shows from another device"],
  ].freeze

  def build
    bin.tap do |root|
      root.child = status_page

      status_page.tap do |page|
        page.child = hint_box

        hint_box.tap do |box|
          HINTS.each { |icon, label| box.append(hint_row(icon, label)) }
        end
      end
    end
  end

  def bin = @bin ||= Adwaita::Bin.new

  def status_page
    @status_page ||= Adwaita::StatusPage.new.tap do |page|
      # Translators: Shows as a noun, meaning Podcast-Shows.
      page.title = "Get Some Shows"
      page.icon_name = APP_ICON
    end
  end

  def hint_box
    @hint_box ||= Gtk::Box.new(:vertical, 6).tap do |box|
      box.halign = :center
    end
  end

  private

    def hint_row(icon_name, text)
      Gtk::Box.new(:horizontal, 12).tap do |row|
        row.append(hint_icon(icon_name))
        row.append(hint_label(text))
      end
    end

    def hint_icon(icon_name)
      Gtk::Image.new(icon_name: icon_name).tap do |image|
        image.add_css_class("dim-label")
        image.accessible_role = :presentation
      end
    end

    def hint_label(text)
      Gtk::Label.new(text).tap do |label|
        label.wrap = true
        label.add_css_class("dim-label")
      end
    end
end
