# frozen_string_literal: true

require "gtk4"
require_relative "xml_parser"

# ReadMoreLabel shows the first lines of a description with a "Read More"
# button, and the whole of it once that button is pressed.
#
# Ported from podcasts-gtk/src/widgets/read_more_label.rs. Upstream is a custom
# widget with its own measure/size_allocate: it keeps both labels parented and
# swaps which one is allocated, and it expands by itself when the space it is
# given would fit the long label anyway. Overriding a widget's layout virtuals
# is not something these bindings offer, so the port is a Box that shows the
# short label plus the button, and swaps in the long label when the button is
# pressed — the same two states, driven by the press rather than by the
# allocation.
#
# The accessible label and description upstream sets on both need
# Gtk::Accessible#update_property, which these bindings do not implement, so
# they are left off here and everywhere else the port would have set one.
class ReadMoreLabel
  SHORT_LINES = 4

  def initialize
    @expanded = false
  end

  def expanded? = @expanded

  def build
    box.tap do |root|
      root.append(short_box)
      root.append(long_label)

      short_box.tap do |short|
        short.append(short_label)
        short.append(button)

        button.signal_connect("clicked") { self.expanded = true }
      end
    end
  end

  # Upstream's init: the whole thing reads as one label to a screen reader.
  def init
    box.focusable = true
    box.accessible_role = :label
    self
  end

  # Upstream's set_label: the first line goes in the short label and the whole
  # text in the long one, both as markup.
  def label=(text)
    XmlParser.escape(text.to_s).then do |markup|
      short_label.markup = markup.lines.first.to_s
      long_label.markup = markup
    end
    text
  end

  def expanded=(value)
    @expanded = value
    short_box.visible = !value
    long_label.visible = value
    value
  end

  def box
    @box ||= Gtk::Box.new(:vertical, 6).tap do |root|
      root.halign = :center
    end
  end

  def short_box
    @short_box ||= Gtk::Box.new(:vertical, 6).tap do |short|
      short.halign = :center
    end
  end

  def short_label
    @short_label ||= Gtk::Label.new.tap do |label|
      label.halign = :center
      label.valign = :center
      label.use_markup = true
      label.wrap = true
      # See https://gitlab.gnome.org/GNOME/gtk/-/issues/4714.
      label.lines = SHORT_LINES
      label.wrap_mode = :word_char
      label.justify = :center
      label.ellipsize = :end
    end
  end

  def long_label
    @long_label ||= Gtk::Label.new.tap do |label|
      label.use_markup = true
      label.justify = :center
      label.wrap = true
      label.wrap_mode = :word_char
      label.valign = :center
      label.halign = :center
      label.visible = false
    end
  end

  def button
    @button ||= Gtk::Button.new(label: "Read More").tap do |read_more|
      read_more.halign = :center
    end
  end
end
