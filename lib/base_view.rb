# frozen_string_literal: true

require "adwaita"

# BaseView is the scroller every page's content sits in.
#
# Ported from podcasts-gtk/src/widgets/base_view.rs: an AdwBin holding a
# ScrolledWindow that never scrolls horizontally, with a 360px minimum width,
# and a `child` property that reaches through to the scroller's child.
class BaseView
  MINIMUM_WIDTH = 360

  def build
    bin.tap do |root|
      root.child = scroller
    end
  end

  # Upstream exposes this both as `set_content` and as the `child` property.
  def content=(widget)
    scroller.child = widget
  end

  def content = scroller.child

  def bin
    @bin ||= Adwaita::Bin.new.tap do |root|
      root.set_size_request(MINIMUM_WIDTH, -1)
    end
  end

  def scroller
    @scroller ||= Gtk::ScrolledWindow.new.tap do |window|
      window.set_policy(:never, :automatic)
    end
  end
end
