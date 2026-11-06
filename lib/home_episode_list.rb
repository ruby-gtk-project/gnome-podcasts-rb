# frozen_string_literal: true

require "adwaita"
require "date"
require_relative "dbqueries"
require_relative "episode_widget"
require_relative "utils"

# HomeEpisodeList is the Home page's list of episodes, grouped by age.
#
# Ported from the HomeEpisodeList half of podcasts-gtk/src/widgets/home_view.rs
# and podcasts-gtk/resources/gtk/home_episode_list.ui: five sections — Today,
# Yesterday, This Week, This Month, Older — each a bold heading over a
# content-styled ListBox, each hidden until it has an episode in it, and a "No
# Results Found" page in place of the whole list when the filter matches
# nothing.
#
# Upstream replaces the whole widget on every reload and lets the old one's
# lazy loading run out; the port loads the page in one pass, so a reload builds
# a fresh list the same way but has nothing to abandon.
class HomeEpisodeList
  PAGE_SIZE = 100
  HEADING_SCALE = 1.5

  SECTIONS = {
    today:     "Today",
    yesterday: "Yesterday",
    week:      "This Week",
    month:     "This Month",
    rest:      "Older",
  }.freeze

  def initialize(app:)
    @app = app
    @rows = {}
  end

  attr_reader :app

  def build
    bin.tap do |root|
      root.child = frame_parent

      frame_parent.tap do |box|
        SECTIONS.each_key { |key| box.append(section_box(key)) }
      end
    end
  end

  # Upstream's load: fetch one page of episodes for the filter and fill the
  # date boxes with them.
  def load(filter)
    @rows = {}
    clear_sections
    split(
      Dbqueries.episodes_widgets_page(
        Utils.ignored_shows,
        filter,
        0,
        PAGE_SIZE,
      ),
    ).then do |groups|
      if groups.values.all?(&:empty?)
        bin.child = empty_page
      else
        bin.child = frame_parent
        groups.each { |key, episodes| fill(key, episodes) }
      end
    end
  end

  # Upstream's update_episode: hand the new state to the row that shows it.
  def update_episode(episode)
    @rows[episode.id].then do |widget|
      if widget
        widget.update_episode_state(episode)
      end
    end
  end

  def episode_widget(episode_id) = @rows[episode_id]

  def bin = @bin ||= Adwaita::Bin.new

  def frame_parent
    @frame_parent ||= Gtk::Box.new(:vertical, 24).tap do |box|
      box.margin_start = 12
      box.margin_end = 12
      box.margin_top = 32
      box.margin_bottom = 32
      box.hexpand = true
    end
  end

  def empty_page
    @empty_page ||= Adwaita::StatusPage.new.tap do |page|
      page.title = "No Results Found"
      page.description = "Try a different search or filters"
      page.icon_name = "system-search-symbolic"
      page.valign = :center
      page.vexpand = true
    end
  end

  def section_box(key)
    section_boxes[key] ||= Gtk::Box.new(:vertical, 6).tap do |box|
      box.visible = false
      box.hexpand = true
      box.append(heading(key))
      box.append(list(key))
    end
  end

  def list(key)
    lists[key] ||= Gtk::ListBox.new.tap do |list_box|
      list_box.hexpand = true
      list_box.activate_on_single_click = true
      list_box.selection_mode = :none
      list_box.add_css_class("content")
      list_box.signal_connect("row-activated") { |_, row| on_row_activated(row) }
    end
  end

  private

    def section_boxes = @section_boxes ||= {}
    def lists = @lists ||= {}

    def heading(key)
      Gtk::Label.new(SECTIONS.fetch(key)).tap do |label|
        label.halign = :start
        label.hexpand = true
        label.attributes = Pango::AttrList.new.tap do |attributes|
          attributes.insert(Pango::AttrWeight.new(:bold))
          attributes.insert(Pango::AttrScale.new(HEADING_SCALE))
        end
      end
    end

    def clear_sections
      SECTIONS.each_key do |key|
        section_box(key).visible = false
        list(key).tap do |list_box|
          while list_box.first_child
            list_box.remove(list_box.first_child)
          end
        end
      end
    end

    def fill(key, episodes)
      unless episodes.empty?
        section_box(key).visible = true
        episodes.each { |episode| list(key).append(row_for(episode)) }
      end
    end

    def row_for(episode)
      EpisodeWidget.new(app: app, episode: episode, add_show_link: true).then do |widget|
        @rows[episode.id] = widget
        widget.build
      end
    end

    # Upstream's row-activated handler: open the clicked episode's
    # description page, the same way EpisodeMenu's "go-to-show" finds a
    # widget's episode back from the row GTK handed it.
    def on_row_activated(row)
      @rows.each_value { |widget| app.go_to_episode_description(widget.episode) if widget.row.equal?(row) }
    end

    # Upstream's split/split_model: today, yesterday, the rest of this week,
    # the rest of this month, then everything older.
    def split(episodes)
      SECTIONS.keys.to_h { |key| [key, []] }.tap do |groups|
        Time.now.then do |now|
          episodes.each { |episode| groups[bucket(now, episode.epoch.localtime)] << episode }
        end
      end
    end

    def bucket(now, stamp)
      days_now = now.to_date.jd
      days_episode = stamp.to_date.jd
      weekday = (now.to_date.cwday - 1)

      if days_episode == days_now
        :today
      elsif days_episode == days_now - 1
        :yesterday
      elsif days_episode >= days_now - weekday
        :week
      elsif now.month == stamp.month && now.year == stamp.year
        :month
      else
        :rest
      end
    end
end
