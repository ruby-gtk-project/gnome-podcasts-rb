# frozen_string_literal: true

require "gtk4"

# EmptyShow is what a show page shows when the feed carries no episodes.
#
# Ported from podcasts-gtk/src/widgets/empty_show.rs and
# podcasts-gtk/resources/gtk/empty_show.ui: a bold, scaled-up title over a
# dimmed subtitle, both centred, and `empty_because_of_filter` swaps the title
# for the filter wording and drops the subtitle.
class EmptyShow
  TITLE = "This show does not have episodes yet"
  SUBTITLE = "If you think this is an error, please consider writing a bug report."
  FILTERED_TITLE = "No results for the active filter."
  TITLE_SCALE = 1.44

  def build
    box.tap do |root|
      root.append(title)
      root.append(subtitle)
    end
  end

  # Upstream's set_empty_because_of_filter.
  def empty_because_of_filter
    title.label = FILTERED_TITLE
    subtitle.visible = false
  end

  def box
    @box ||= Gtk::Box.new(:vertical, 6).tap do |root|
      root.halign = :center
      root.valign = :center
      root.hexpand = true
      root.vexpand = true
      root.margin_start = 6
      root.margin_end = 6
      root.margin_top = 6
      root.margin_bottom = 6
    end
  end

  def title
    @title ||= Gtk::Label.new(TITLE).tap do |label|
      label.wrap = true
      label.justify = :center
      label.attributes = title_attributes
    end
  end

  def subtitle
    @subtitle ||= Gtk::Label.new(SUBTITLE).tap do |label|
      label.wrap = true
      label.justify = :center
      label.add_css_class("dim-label")
    end
  end

  private

    def title_attributes
      Pango::AttrList.new.tap do |attributes|
        attributes.insert(Pango::AttrWeight.new(Pango::Weight::BOLD))
        attributes.insert(Pango::AttrScale.new(TITLE_SCALE))
      end
    end
end
