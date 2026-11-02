# frozen_string_literal: true

require "adwaita"
require "gtk4"
require_relative "discovery_found_podcast"

# DiscoverySearchResults is the page a search lands on: one row per podcast
# the platforms found, or a line saying there were none.
#
# Ported from podcasts-gtk/src/widgets/discovery_search_results.rs and
# podcasts-gtk/resources/gtk/discovery_search_results.ui: a navigation page
# tagged "search_results" with a toolbar view, a header bar, and a scrolling
# clamp of 700px around a boxed-list ListBox. With nothing found the list goes
# away and the "No results found." label takes its place.
class DiscoverySearchResults
  TAG = "search_results"
  TITLE = "Search results"
  CLAMP_SIZE = 700

  def initialize(app:, results:)
    @app = app
    @results = results
  end

  attr_reader :app, :results

  def build
    page.tap do
      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = scrolled_window

        scrolled_window.child = clamp
        clamp.child = container

        container.tap do |box|
          box.append(list)
          box.append(no_results_label)

          results.each do |found|
            list.append(DiscoveryFoundPodcast.new(app: app, podcast: found).build)
          end
        end
      end

      if results.empty?
        no_results_label.visible = true
        list.visible = false
      end
    end
  end

  # Adwaita::NavigationPage takes its child positionally, so the toolbar view
  # is built before the page that holds it.
  def page
    @page ||= Adwaita::NavigationPage.new(toolbar_view, TITLE).tap do |navigation_page|
      navigation_page.tag = TAG
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def scrolled_window
    @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |window|
      window.vexpand = true
      window.hexpand = true
      window.hscrollbar_policy = :never
    end
  end

  def clamp
    @clamp ||= Adwaita::Clamp.new.tap do |clamped|
      clamped.vexpand = true
      clamped.maximum_size = CLAMP_SIZE
    end
  end

  def container
    @container ||= Gtk::Box.new(:vertical, 5).tap do |box|
      box.vexpand = true
      box.margin_top = 18
      box.margin_bottom = 18
      box.margin_start = 18
      box.margin_end = 18
    end
  end

  def list
    @list ||= Gtk::ListBox.new.tap do |list_box|
      list_box.selection_mode = :none
      list_box.add_css_class("boxed-list")
    end
  end

  def no_results_label
    @no_results_label ||= Gtk::Label.new("No results found.").tap do |label|
      label.visible = false
    end
  end
end
