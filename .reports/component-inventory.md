# gnome-podcasts-rb — upstream component inventory

Upstream: `origin/main` (GNOME Podcasts, Rust + gtk-rs, `podcasts-gtk/` front end,
`podcasts-data/` back end). Port: the `ruby` branch, flat `lib/<thing>.rb` per the
`gnome-contacts-rb` pilot.

Scope note: upstream splits nearly every component across **two** files — a
`podcasts-gtk/src/widgets/*.rs` subclass with `#[template_child]`s and callbacks,
plus a `podcasts-gtk/resources/gtk/*.ui` GtkBuilder tree carrying the widget
types, CSS classes and accessibility labels. The Ruby port merges each pair into
one `lib/*.rb`, so the rows below are unioned per port file.

## State of the port

`lib/` on `ruby` now holds 45 files: the data layer, the application, the main
window and the three content pages, ported in commit `f0c12cc6`.

Present (one `lib/*.rb` per upstream component, every file carrying the
`Ported from podcasts-…` comment the house style asks for):

- **Application and window** — `gnome_podcasts/application.rb`, `main_window.rb`,
  `main_menu.rb`, `about_dialog.rb`, `shortcuts_dialog.rb`
- **Content** — `content_stack.rb`, `base_view.rb`, `home_view.rb`,
  `home_episode_list.rb`, `shows_view.rb`, `queue_view.rb`, `show_widget.rb`,
  `show_menu.rb`, `filter_menu.rb`
- **Episodes** — `episode_widget.rb`, `episode_menu.rb`, `download_progress.rb`,
  `read_more_label.rb`
- **Empty states** — `empty_view.rb`, `empty_show.rb`
- **Support** — `settings.rb`, `style.rb`, `icons.rb`, `opml_dialogs.rb`,
  `download_manager.rb`, `utils.rb`, `xdg_dirs.rb`
- **Data layer** — `database.rb`, `dbqueries.rb`, `show.rb`, `episode.rb`,
  `source.rb`, `queue_item.rb`, `feed.rb`, `feed_manager.rb`, `opml.rb`,
  `parser.rb`, `pipeline.rb`, `xml_parser.rb`, `data_utils.rb`, `errors.rb`

Three of the present files are **partial**, and each knows it:

- `gnome_podcasts/application.rb` carries 11 of upstream's 25 accelerators and
  none of the player, chapters or discovery actions. Upstream's `Action` channel
  is replaced by direct method calls on this object.
- `main_window.rb` has the toast overlay, navigation view, both view switchers,
  the `toolbar` center box and the narrow breakpoint — but **not** the
  `AdwMultiLayoutView`, its `wide`/`narrow` layouts, the four layout slots, the
  `AdwBottomSheet` or the two player breakpoints, because all of those exist to
  host the player.
- `shortcuts_dialog.rb` lists 8 of upstream's 14 items: Navigation and General,
  minus "Go To Discovery Page". The whole Player section is absent.

Still entirely missing (every row below marked `no`): the **player** stack
(10 files), the **discovery** pages (3 files), the **episode description** page,
the **chapters** page and both parsers, **sync preferences** and the whole
Nextcloud sync data layer, `download_covers`, `thumbnail_generator`, and the
`po/` catalogue.

## Environment facts verified in the fork's dev shell

- GTK 4.22.4; every Adwaita type upstream needs is bound and present:
  `MultiLayoutView`, `Layout`, `LayoutSlot`, `BottomSheet`, `ToggleGroup`,
  `ShortcutsDialog`, `Spinner`, `ToastOverlay`, `NavigationView`, `ViewStack`,
  `Breakpoint`. `Gtk::GridView` present.
- `require "gst"` fails with `LoadError` — **there is no GStreamer binding in the
  dev shell**, so `player.rs` has no playback engine to port onto yet.

## Window and application

| Upstream | → port file | Kind | Exists |
|---|---|---|---|
| `src/app.rs`, `src/widgets/aboutdialog.rs` (app half) | `lib/gnome_podcasts/application.rb` | application | partial |
| `src/window.rs` + `resources/gtk/window.ui` (template) | `lib/main_window.rb` | window | partial |
| `resources/gtk/window.ui` (`<menu id="menu">`) | `lib/main_menu.rb` | menu | yes |
| `src/widgets/aboutdialog.rs` | `lib/about_dialog.rb` | dialog | yes |
| `resources/gtk/shortcuts-dialog.ui` (no backing source) | `lib/shortcuts_dialog.rb` | dialog | partial |

### `src/app.rs` — `PdApplication(Adw.Application)`

Actions installed: `app.quit`, `app.go-to-episode`, `app.go-to-show`,
`app.go-to-chapters`, `app.undo-mark-all`, `app.undo-remove-show`, plus
`app.shortcuts` referenced from the main menu.

Accelerators: `app.quit` `<primary>q`; `win.open-search` `<primary>f`;
`win.refresh` `<primary>r`/`F5`; `win.toggle-pause` `<primary>space`;
`win.seek-forwards` `<primary>Right`; `win.seek-backwards` `<primary>Left`;
`win.raise-playback-rate` `<primary>greater`; `win.lower-playback-rate`
`<primary>less`; `win.go-to-home` `F1`/`<alt>1`; `win.go-to-shows` `F2`/`<alt>2`;
`win.go-to-queue` `F3`/`<alt>3`; `win.go-to-discovery` `F4`/`<alt>4`/`<primary>n`;
`win.import` `<primary>o`; `win.export` `<primary>e`; `window.close` `<primary>w`.

Also owns the `Action` message loop that pushes pages, raises toasts
(`adw::Toast` "Copied URL to clipboard!", error toasts) and the devel CSS class.

### `src/window.rs` + `window.ui` — `PdMainWindow(AdwApplicationWindow)`

| Widget | × | CSS | Signals / behaviour |
|---|---:|---|---|
| `Adw.ApplicationWindow` | 1 | `devel` (nightly build only) | 360×294 minimum; geometry persisted to GSettings |
| `Adw.Breakpoint` | 3 | — | `min-width: 800sp` (`player_breakpoint`, `apply`/`unapply`), `max-width: 800sp` → narrow layout, `max-width: 550sp` → drop header title widget + narrow |
| `Adw.ToastOverlay` | 1 | — | every toast in the app lands here |
| `Adw.MultiLayoutView` | 1 | — | layouts `wide` / `narrow` |
| `Adw.Layout` | 2 | — | `wide` (`AdwToolbarView`), `narrow` (`AdwBottomSheet`) |
| `Adw.LayoutSlot` | 4 | — | `content` ×2, `toolbar` ×2 |
| `Adw.ToolbarView` | 2 | — | `player_toolbar_view`, `content_view` |
| `Adw.BottomSheet` | 1 | — | `can-open=False`; `connect_open_notify`; sheet is `PdSheetBase`; content margin bound to `bottom-bar-height` |
| `Adw.NavigationView` | 1 | — | `connect_popped`; pages tagged `content`, `show` |
| `Adw.NavigationPage` | 2 | — | "Podcasts" (tag `content`), "Show" (tag `show`) |
| `Adw.HeaderBar` | 1 | — | `main_header`; title widget cleared at 550sp |
| `Adw.ViewSwitcher` | 2 | — | `top_switcher` (policy wide), `bottom_switcher` |
| `Gtk.Button` | 1 | — | tooltip "Add a New Feed", `list-add-symbolic`, `win.go-to-discovery` |
| `Gtk.MenuButton` | 1 | — | `hamburger`, `open-menu-symbolic`, primary, menu-model `menu` |
| `Adw.ViewStack` + `Adw.ViewStackPage` | 1 + 2 | — | `filter_stack`: `home` → `filter_home`, `shows` → `filter_shows` |
| `Gtk.Box` | 1 | — | `toolbar_box`, vertical |
| `Gtk.CenterBox` | 1 | `toolbar` | `bottom_switcher_bar`, hidden unless mobile + root page |
| `PdFilterMenu` | 2 | — | composite, see `lib/filter_menu.rb` |
| `PdPlayerWrapper` | 1 | — | composite |
| `PdSheetBase` | 1 | — | composite |

Actions installed on the window class: `win.refresh`, `win.import` (async),
`win.export` (async), `win.goto-sync-preferences`, `win.about`, `win.play`,
`win.pause`, `win.toggle-pause`, `win.seek-forwards`, `win.seek-backwards`,
`win.set-rate` (parameterised), `win.go-to-home`, `win.go-to-shows`,
`win.go-to-queue`, `win.go-to-discovery`, `win.close-bottom-sheet`,
`win.raise-playback-rate`, `win.lower-playback-rate`, `win.open-search`, and one
further parameterised action at `window.rs:230`. Properties `is-root-page` and
`is-mobile-layout` drive the bottom switcher's visibility.

Main menu items: "_Check for New Episodes" (`win.refresh`, `<primary>r`),
"_Import Shows" (`win.import`), "_Export Shows" (`win.export`),
"Sync Preferences" (`win.goto-sync-preferences`) | "_Keyboard Shortcuts"
(`app.shortcuts`), "_About Podcasts" (`win.about`).

### `resources/gtk/shortcuts-dialog.ui` — `AdwShortcutsDialog`

3 `AdwShortcutsSection` / 14 `AdwShortcutsItem`:
Navigation — Go to Home Page, Go to Shows Page, Go to Queue Page, Go To
Discovery Page. Player — Toggle Pause, Seek Forwards, Seek Backwards, Raise
Playback Speed, Lower Playback Speed. General — Check for new episodes, Quit the
application, Import Subscriptions, Export Subscriptions, Search.

## Main content views

| Upstream | → port file | Kind | Exists |
|---|---|---|---|
| `src/widgets/content_stack.rs` | `lib/content_stack.rb` | view stack + empty-state switch | yes |
| `src/widgets/base_view.rs` | `lib/base_view.rb` | widget (scrolled `AdwBin` base) | yes |
| `src/widgets/home_view.rs` + `home_view.ui` | `lib/home_view.rb` | page | yes |
| `resources/gtk/home_episode_list.ui` | `lib/home_episode_list.rb` | list (date-bucketed) | yes |
| `src/widgets/shows_view.rs` | `lib/shows_view.rb` | page (`GridView` of covers) | yes |
| `src/widgets/queue_view.rs` + `queue_view.ui` | `lib/queue_view.rb` | page + empty state | yes |
| `src/widgets/show.rs` + `show_widget.ui` | `lib/show_widget.rb` | page | yes |
| `src/widgets/show_menu.rs` + `show_menu.ui` | `lib/show_menu.rb` | menu + action group | yes |
| `resources/gtk/secondary_menu.ui` | not ported (noted in `lib/show_menu.rb`) | menu (dead: all three `action` attributes are commented out upstream) | n/a — deliberately skipped |
| `src/widgets/filter_menu.rs` + `filter_menu.ui` | `lib/filter_menu.rb` | menu + stateful actions | yes |

`content_stack.rs`: `Adw.ViewStack` with pages `home` ("New"), `shows`
("Shows"), `queue` ("Queue"); a `Gtk.Overlay` holding a `Gtk.ProgressBar` with
CSS `osd` and tooltip "Fetching feeds…"; `connect_visible_child_notify` ×2
switching the header's filter stack; `check_empty_state` swaps in `PdEmptyView`.

`home_view.ui`: `AdwToolbarView` → `Gtk.SearchBar` + `Gtk.SearchEntry`
(width 300, search-delay 500) over a `PdBaseView` → `Adw.Clamp` (max 700) →
`AdwBin` container.

`home_episode_list.ui`: five identical date buckets — Today, Yesterday, This
Week, This Month, Older — each a hidden `Gtk.Box` (spacing 6) with a bold
1.5-scale `Gtk.Label` and a `Gtk.ListBox` (CSS `content`, selection none,
activate-on-single-click, accessible label matching the heading). **Repeater:**
each list is filled with one `PdEpisode` per episode in that bucket.

`shows_view.rs`: built in code — `Gtk.GridView` (CSS `shows-grid`, accessible
label "Shows") over a `Gtk.NoSelection` of `ShowCoverModel`, a
`Gtk.SignalListItemFactory` whose setup makes a `Gtk.Picture` with CSS `flat`,
`rounded-big`, `show-button`; a `Gtk.SearchEntry`; an `Adw.StatusPage` empty
state titled "No Results Found" / "Try a different search or filters"; an
`Adw.ToolbarView` container. Signals: `grid.connect_activate`,
`filter_menu.connect_filter_changed`, `search_entry.connect_search_changed`.

`queue_view.ui`: `PdBaseView` → `Adw.Clamp` → `Gtk.Box` with an
`Adw.StatusPage` (`empty_queue_status_page`) and a `Gtk.ListBox` (`boxed-list`).
**Repeater:** one `PdEpisode` per queued episode, reorderable by drag.

`show_widget.ui`: `AdwToolbarView` → `Adw.HeaderBar` with a `Gtk.MenuButton`
(`secondary_menu`) and a `PdFilterMenu`; `Gtk.SearchBar` + `Gtk.SearchEntry`;
`PdBaseView` → `Adw.Clamp` ×3 → cover `Gtk.Image` (`rounded-big`),
`PdReadMoreLabel`, and an `AdwBin` whose child is a `Gtk.ListBox` (CSS
`content`) of `PdEpisode` rows. Signals: `filter_menu.connect_filter_changed`,
`search_entry.connect_search_changed`.

`show_menu.rs` + `show_menu.ui`: `Gio.SimpleActionGroup` `show` with
`show.open-website` ("Open Website"), `show.mark-played` ("Mark All as Played"),
`show.unsubscribe` ("Unsubscribe"). Both destructive ones raise an `adw::Toast`
with an Undo button ("Marked all episodes as listened", "Unsubscribed from {}")
and commit on `connect_dismissed`.

`filter_menu.rs` + `filter_menu.ui`: `AdwBin` → `Gtk.Box` with a
`Gtk.ToggleButton` (`search_button`), a `Gtk.Overlay` whose overlay is a
`Gtk.Box` with CSS `circle-overlay`, and a `Gtk.MenuButton`. Stateful actions
`filter.order`, `filter.played`, `filter.downloaded` (default `"all"`), custom
`filter-changed` signal. Two menu models: episodes — Newest First / Oldest
First; All / Played / Not Played; All / Downloaded / Not Downloaded. Shows —
Alphabetical / Reversed; All / Completed / Not Completed; All / Downloaded /
Not Downloaded.

## Episodes

| Upstream | → port file | Kind | Exists |
|---|---|---|---|
| `src/widgets/episode.rs` + `episode_widget.ui` | `lib/episode_widget.rb` | row | yes |
| `src/widgets/episode_menu.rs` + `episode_menu.ui` | `lib/episode_menu.rb` | menu + action group | yes |
| `src/widgets/episode_description.rs` + `episode_description.ui` | `lib/episode_description.rb` | page | no |
| `src/widgets/download_progress_bar.rs` | `lib/download_progress.rb` | widget | yes |
| `src/widgets/read_more_label.rs` | `lib/read_more_label.rb` | widget | yes |
| `src/episode_description_parser.rs` | `lib/episode_description_parser.rb` | helper (HTML → Pango) | no |
| `src/chapter_parser/{mod,id3,extended_comment}.rs` | `lib/chapter_parser.rb` | helper | no |

`episode_widget.ui` — `PdEpisode(GtkListBoxRow)`: `Gtk.Revealer`
(`main_revealer`); drag/drop target revealers with `AdwBin`s carrying CSS
`drop-target` + `drop-target-top` / `drop-target-bottom`; a `drag_handle` box
with a `dimmed` `Gtk.Image`; cover `Gtk.Image` (`rounded-small`); title
`Gtk.Label` (gains/loses `dim-label` with played state); `played_checkmark`
`Gtk.Image` (`dim-label`); subtitle and `download_progress` labels (`caption`);
five flat buttons — `play`, `pause`, `cancel`, `add_to_queue`, `text_only`; and
a `PdDownloadProgress`. The drag icon gets CSS `card` +
`dragged-episode-icon`. Duration formatted "{} min".

`episode_menu.ui` — `Gio.SimpleActionGroup` `episode`, eight actions, each added
only when applicable: `episode.go-to-show` ("Go to Show"),
`episode.copy-episode-url` ("Copy Episode URL"), `episode.mark-as-played`
("Mark as Played"), `episode.mark-as-unplayed` ("Mark as Unplayed"),
`episode.download` ("Download"), `episode.delete` ("Delete"),
`episode.move-up-in-queue` ("Move Up in Queue"), `episode.move-down-in-queue`
("Move Down in Queue").

`episode_description.ui` — `PdEpisodeDescription(AdwNavigationPage)`:
`AdwToolbarView` → `Adw.HeaderBar` with a `Gtk.MenuButton`; `Adw.Clamp` →
cover `Gtk.Image` (`rounded-small`), `podcast_title` (`dim-label`),
`episode_title` (`heading`), `episode_duration` (`episode_duration`); a
`button-row` box with five pill buttons — `stream_button`, `play_button`,
`pause_button`, `download_button`, `delete_button`, each an
`AdwButtonContent` — plus a `cancel_button` (`cancel-button`, `pill`) wrapping a
`cancel-button-text` box and a `PdDownloadProgress` (`in-button-progress`);
description `Gtk.Label` (`episode_description_label`, `document`) and an
episode-specific `Gtk.Picture` (`episode_description`).

## Player

| Upstream | → port file | Kind | Exists |
|---|---|---|---|
| `src/widgets/player_wrapper.rs` + `player_wrapper.ui` | `lib/player_wrapper.rb` | widget (big/small stack) | no |
| `src/widgets/player_big.rs` + `player_big.ui` | `lib/player_big.rb` | widget | no |
| `src/widgets/player_small.rs` + `player_small.ui` | `lib/player_small.rb` | widget | no |
| `src/widgets/player_rate.rs` + `player_rate.ui` | `lib/player_rate.rb` | menu button | no |
| `src/widgets/sheet_base.rs` + `sheet_base.ui` | `lib/sheet_base.rb` | bottom sheet | no |
| `src/widgets/sheet_player.rs` + `sheet_player.ui` | `lib/sheet_player.rb` | sheet page | no |
| `src/widgets/sheet_description.rs` + `sheet_description.ui` | `lib/sheet_description.rb` | sheet page | no |
| `src/widgets/chapters.rs` + `chapters.ui` | `lib/chapters.rb` | page + list | no |
| `src/player.rs` | `lib/player.rb` | playback controller (non-widget) | no |
| `src/player_mpris.rs` | `lib/player_mpris.rb` | MPRIS / desktop integration | no |

`player_wrapper.ui`: `AdwBin` → `Gtk.Stack` holding `PdPlayerBig` and
`PdPlayerSmall`, CSS `toolbar`.

`player_big.ui`: `rewind` / `forward` buttons and a `play_pause` `Gtk.Stack`
with `play` and `pause`, all `flat circular taller-button`; a flat
`cover_button` wrapping a `rounded-small` `Gtk.Image`; `show` (`caption`) and
`episode` (`caption-heading`) labels; a `Gtk.Scale` slider; a timer box with
`progressed` / `separator` / `duration` labels; a `chapters_button`; a
`PdPlayerRate`.

`player_small.ui`: `Gtk.ProgressBar` (`playback-progress`); flat `cover_button`
with `rounded-small` cover; `show`/`episode` labels; `play_pause` stack with
flat `play` and `pause`.

`player_rate.ui`: `AdwBin` → flat `Gtk.MenuButton`; menu of seven rates —
2.00×, 1.75×, 1.50×, 1.25×, 1.00×, 0.90×, 0.75× — all targeting `win.set-rate`;
label formatted "{:.2}×".

`sheet_base.ui`: `AdwToolbarView` → `Adw.HeaderBar` + `Adw.ViewStack` with three
pages (`PdSheetPlayer`, `PdSheetDescription`, `PdChapters`), and a
`Gtk.CenterBox` bottom bar holding a `PdPlayerRate` and an `Adw.ToggleGroup` of
three `Adw.Toggle`s (the third, `chapters_toggle`, only when chapters exist).

`sheet_player.ui`: `rounded-big` cover; `episode` (`heading`) and `show`
(`dim-label`) labels; `progressed` / `duration` labels (`numeric caption`)
around a `Gtk.Scale`; `rewind`, `play_pause` stack (`play`/`pause`), `forward`
buttons whose images carry `image-button` + `circular`.

`sheet_description.ui`: scrolled `Adw.Clamp` with `episode` (`heading`), `show`
(`dim-label`) and a description `Gtk.Label` (`episode_description_label`,
`document`).

`chapters.ui` + `chapters.rs`: `Adw.Clamp` → `episode` (`heading`) and `show`
(`dim-label`) labels over a `Gtk.ListBox` (`boxed-list`). **Repeater:** one row
per chapter, each `property`-classed, with a tooltip "Currently playing chapter"
on the active one. Installs one parameterised action (`chapters.rs:144`) and is
pushed as `adw::NavigationPage::with_tag(…, "Chapters", "chapters")`.

## Discovery

| Upstream | → port file | Kind | Exists |
|---|---|---|---|
| `src/widgets/discovery_page.rs` + `discovery_page.ui` | `lib/discovery_page.rb` | page | no |
| `src/widgets/discovery_search_results.rs` + `discovery_search_results.ui` | `lib/discovery_search_results.rb` | page | no |
| `resources/gtk/discovery_found_podcast.ui` | `lib/discovery_found_podcast.rb` | row | no |

`discovery_page.ui`: `AdwNavigationPage` → `AdwToolbarView` → `Adw.HeaderBar`;
`Adw.Clamp` → `boxed-list` box with a `heading` label, `entry_description`
(`dim-label`), a `Gtk.Entry` (`entry`, gains/loses CSS `error`), a
`search_button`, an `Adw.Spinner` (`loading_spinner`, announced "Loading…"), an
error `Gtk.Label` (`no_platforms_selected_label`, CSS `error`), and an
`Adw.PreferencesGroup` (`list`). **Repeater:** one `Adw.SwitchRow` per entry in
`ALL_PLATFORM_IDS`, state read from and written to the `discovery_settings`
table. Also accepts iTunes and SoundCloud URLs via `itunes_to_rss` /
`soundcloud_to_rss`.

`discovery_search_results.ui`: `AdwNavigationPage` → `AdwToolbarView` →
`Adw.HeaderBar`; `Adw.Clamp` → `Gtk.ListBox` (`boxed-list`) plus a `no_results`
label. **Repeater:** one `PdDiscoveryFoundPodcast` per result; subscribing
announces "Subscribing to feed…".

`discovery_found_podcast.ui`: `AdwPreferencesRow` (CSS `found-podcast`) with a
`cover` `Gtk.Image`; `title` (`title`), `author` (`subtitle`), `description`
(`dim-label`), an `episode_count` box (two `subtitle` labels), `feed_url` and
`last_publication` (`subtitle`); a `subscribe_stack` `Gtk.Stack` holding a
`subscribe` `Gtk.Button` and an `Adw.Spinner`.

## Empty and error states

| Upstream | → port file | Kind | Exists |
|---|---|---|---|
| `src/widgets/empty_view.rs` + `empty_view.ui` | `lib/empty_view.rb` | empty state | yes |
| `src/widgets/empty_show.rs` + `empty_show.ui` | `lib/empty_show.rb` | empty state | yes |

`empty_view.ui`: `AdwBin` → `Adw.StatusPage` titled "Get Some Shows" with two
hint rows, each a `dim-label` `Gtk.Image` (`list-add-symbolic`,
`open-menu-symbolic`, both `accessible_role=presentation`) beside a `dim-label`
wrapped `Gtk.Label` — "Add new shows via feed URL", "Import shows from another
device".

`empty_show.ui`: a centred `Gtk.Box` with a bold 1.44-scale `title`
("This show does not have episodes yet") and a `dim-label` `subtitle` ("If you
think this is an error, please consider writing a bug report."). `empty_show.rs`
also retitles it "No results for the active filter." when a filter is active.

Further error surfaces, none of which has a dedicated file: `win.import`
failures ("Failed to parse the imported file {}"), `win.export` failures
("Failed to export podcasts"), feed subscribe failures ("Failed to subscribe to
feed: {}"), and the sync-database failure toast in `show_menu.rs`. All route
through `app.rs`'s toast handler into the window's `AdwToastOverlay`.

## Preferences and sync

| Upstream | → port file | Kind | Exists |
|---|---|---|---|
| `src/widgets/sync_preferences.rs` + `sync_preferences.ui` | `lib/sync_preferences.rb` | preferences page | no |
| `src/settings.rs` + `resources/org.gnome.Podcasts.gschema.xml.in` | `lib/settings.rb` | settings | yes |

`sync_preferences.ui` — `PdSyncPreferences(AdwNavigationPage)`, CSS
`sync_preferences`: header with a `logout` `Gtk.Button` (`destructive-action`);
`connection_info` `Adw.PreferencesGroup` with an `Adw.ActionRow` + `last_sync`
label (placeholder "Never"), an `Adw.SwitchRow` (`active`), two read-only
`Adw.EntryRow`s (`server_label`, `user_label`, both `no-edit-icon`) and a
`sync_now` pill button; `login_group` with an `Adw.ActionRow`, an
`Adw.ToggleGroup` of two `Adw.Toggle`s, `server` / `username` `Adw.EntryRow`s, a
`Adw.PasswordEntryRow`, and `login_password` / `login_browser` pill buttons; a
`loading_info` box with `loading_label` and `Adw.Spinner`. Loading messages:
"Logging in...", "Waiting for browser login...", "Logging out...",
"Synchronizing now...", "Refreshing feeds...".

GSettings (`org.gnome.Podcasts`, 8 keys + the `timePeriods` enum of
seconds/minutes/hours/days/weeks/months): `persist-window-geometry-{height,width,maximized}`
(640/860/false), `refresh-interval` (true), `refresh-interval-time` (1, 1–100),
`refresh-interval-period` ('hours'), `refresh-on-startup` (true),
`cleanup-age-time` (2, 1–100), `cleanup-age-period` ('days'). Only the geometry
keys are read by widget code today; the refresh and cleanup keys have **no UI**
upstream, so the port needs no preferences dialog for them.

## Dialogs and non-widget support

| Upstream | → port file | Kind | Exists |
|---|---|---|---|
| `src/utils.rs` (import/export `Gtk.FileDialog`s) | `lib/opml_dialogs.rb` | dialogs | yes |
| `src/manager.rs` | `lib/download_manager.rb` | download manager | yes |
| `src/download_covers.rs` | `lib/download_covers.rb` | helper | no |
| `src/thumbnail_generator.rs` | `lib/thumbnail_generator.rb` | helper | no |
| `resources/gtk/style.css` | `lib/style.rb` (CSS inline, loaded by a `Gtk::CssProvider`) | stylesheet | yes |
| `podcasts-gtk/po/` (45 locales, `POTFILES.in` listing 23 `.ui` + 3 resource + 23 Rust files) | `po/` + a gettext wiring in `lib/gnome_podcasts.rb` | translations | no |
| `podcasts-data/` (whole crate) | `lib/` data layer (schema, dbqueries, feed/OPML parsing, discovery, Nextcloud sync, models) | back end | partial — schema, dbqueries, models, feed/OPML parsing, downloader present; discovery, Nextcloud sync and the chapter parsers absent |

Import dialog: `Gtk.FileDialog`, OPML `Gtk.FileFilter` named "OPML file",
accept label "_Import". Export dialog: same filter, title "Export shows to…",
accept label "_Export", initial name "gnome-podcasts-exported-shows", OPML title
"GNOME Podcasts Subscriptions".

`style.css` defines these classes for the port to reproduce: `boxed-list`,
`circle-overlay`, `dragged-episode-icon`, `drop-target`, `episode_description`,
`episode_description_label`, `in-button-progress`, `no-edit-icon`,
`rounded-big`, `rounded-small`, `show-button`, `shows-grid`, `taller-button`,
plus element rules on `popover`, `progressbar`, `row` and `searchbar`.

Relative-time strings in `utils.rs` that the port must reproduce (plural forms):
"Just now", "{} minute(s) ago", "{} hour(s) ago", "{} day(s) ago",
"{} month(s) ago", "{} year(s) ago".

## Blockers

1. **No GStreamer binding in the dev shell.** `require "gst"` raises
   `LoadError`, so `src/player.rs`, `player_mpris.rs` and every play/pause/seek
   path have no engine. The player widgets can be built and wired to a stub, but
   audio parity is blocked until the flake provides a `gst` gem. This also holds
   back `main_window.rb`'s `AdwMultiLayoutView` / `AdwBottomSheet` half, which
   exists only to host the player, and the Player section of
   `shortcuts_dialog.rb`.
2. **No covers anywhere yet.** `src/download_covers.rs` and
   `src/thumbnail_generator.rs` are unported, so `shows_view.rb`,
   `show_widget.rb` and `episode_widget.rb` all render the icon fallback in place
   of artwork. Three in-tree comments point at `lib/download_covers.rb` as the
   file that fixes it.
3. **`podcasts-data` is ported only as far as the local database.** Present:
   the schema and its 17 migrations, `dbqueries`, the five models, RSS/Atom feed
   parsing, OPML import/export, the downloader. Absent: iTunes and fyyd
   discovery (`src/discovery/`), the whole Nextcloud GPodder sync
   (`src/nextcloud_sync/`, `src/models/sync/`), and the ID3 /
   extended-comment chapter parsers. The discovery pages and the sync
   preferences page cannot be ported before their data layer.
4. **MPRIS / `Gio::DBus` desktop integration** (`player_mpris.rs`) has no
   established pattern in the pilot ports.
5. **Drag-and-drop queue reordering** in `episode_widget.ui` (two drop-target
   revealers, a drag handle, a `card dragged-episode-icon` drag icon) needs
   `Gtk::DragSource`/`DropTarget` wiring the pilot does not demonstrate. The
   queue rows exist in `queue_view.rb`; the reordering does not.
6. **Translations are untouched.** 45 locales exist upstream; the port has no
   `po/` directory and no gettext call in any of the 45 `lib/*.rb` files, so
   every string in the inventory above is currently English-only. The
   `# Translators:` comments upstream carries are preserved in `main_menu.rb`
   and `shortcuts_dialog.rb`, which is as far as it goes.
7. **`secondary_menu.ui` is dead upstream** — its three items have their
   `action` attributes commented out. `lib/show_menu.rb` records this and does
   not port it; do not invent actions for it.
8. **No `.ui` files by house rule.** The remaining 13 unported GtkBuilder trees
   (the 8 player/sheet/chapters ones, the 3 discovery ones,
   `episode_description.ui` and `sync_preferences.ui`) must be transcribed into
   memoized Ruby builders by hand. The Adwaita types are all present (verified
   above), so this is volume, not capability.
