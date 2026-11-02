# frozen_string_literal: true

require "gtk4"

# Icons registers the app's own icons with the icon theme.
#
# Ported from podcasts-gtk/resources/icons/meson.build, which installs the
# app icon and the symbolic variants that ship with the app rather than with
# adwaita-icon-theme — the funnel the filter menu uses is one of them, and it
# is not in the system theme at all.
#
# Upstream reaches them through its GResource bundle; the port keeps them as
# files under data/icons, laid out as a hicolor theme, and adds that directory
# to the icon theme's search path. The path is computed from this file, so it
# resolves both from a checkout and from an installed tree.
module Icons
  SEARCH_PATH = File.expand_path("../data/icons", __dir__)

  class << self
    def load
      Gdk::Display.default.then do |display|
        if display
          Gtk::IconTheme.get_for_display(display).add_search_path(SEARCH_PATH)
        end
      end
    end

    def available?(name)
      Gdk::Display.default.then do |display|
        !display.nil? && Gtk::IconTheme.get_for_display(display).has_icon?(name)
      end
    end
  end
end
