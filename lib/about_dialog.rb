# frozen_string_literal: true

require "adwaita"
require_relative "gnome/podcasts/rb/version"

# AboutDialog is the about window.
#
# Ported from podcasts-gtk/src/widgets/aboutdialog.rs, keeping its credits
# lists, links and license. The version is the port's own, and the port is
# named in the developers list below upstream's, because the dialog has to
# describe the program the user is actually running.
class AboutDialog
  APP_ID = "org.rubygtkproject.GnomePodcasts"

  # Upstream's list, alphabetical, plus the port.
  DEVELOPERS = [
    "Alexandre Franke",
    "Carlos Soriano",
    "Constantin Nickel",
    "Daniel García Moreno",
    "Felix Häcker",
    "Gabriele Musco",
    "Ivan Augusto",
    "James Wykeham-Martin",
    "Jordan Petridis",
    "Jordan Williams",
    "Julian Hofer",
    "Julian Sparber",
    "Matthew Martin",
    "Piotr Drąg",
    "Rowan Lewis",
    "Zander Brown",
    "ruby-gtk-project (Ruby port)",
  ].freeze

  DESIGNERS = ["Tobias Bernard", "Sam Hewitt"].freeze

  def initialize(window)
    @window = window
  end

  # Builds the dialog and shows it over the window it was asked for, which is
  # what upstream's `about_dialog(window)` does.
  def present
    dialog.present(@window)
    dialog
  end

  def dialog
    @dialog ||= Adwaita::AboutDialog.new.tap do |about|
      about.application_icon = APP_ID
      about.application_name = "Podcasts"
      about.comments = "Podcast Client for the GNOME Desktop."
      about.copyright = "© 2017-2021 Jordan Petridis"
      about.license_type = Gtk::License::GPL_3_0
      about.version = Gnome::Podcasts::Rb::VERSION
      about.website = "https://gitlab.gnome.org/World/podcasts"
      about.issue_url = "https://gitlab.gnome.org/World/podcasts/-/issues"
      about.developer_name = "Jordan Petridis, et al."
      about.developers = DEVELOPERS
      about.designers = DESIGNERS
      about.translator_credits = "translator-credits"
    end
  end
end
