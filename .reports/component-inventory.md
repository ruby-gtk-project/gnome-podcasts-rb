# Upstream component inventory — gnome-podcasts-rb

Surveyed against `origin/main` (Rust/gtk-rs, GNOME Podcasts) from the `ruby`
branch's current `lib/`. Per `component-identification`: the unit is the
upstream `.rs` (+ its `.ui` where one exists) mapped to the one `lib/*.rb`
file that should hold it. No app code was written for this pass.

Legend: ✅ exists in `lib/`, ⚠️ exists but incomplete/stubbed, ❌ missing entirely.

## Window / app shell

| Upstream | → lib/*.rb | Kind | Exists? |
|---|---|---|---|
| `podcasts-gtk/src/window.rs` + `resources/gtk/window.ui` | `lib/main_window.rb` | window | ✅ |
| `podcasts-gtk/src/app.rs` | `lib/gnome_podcasts/application.rb` | application | ✅ |
| `podcasts-gtk/src/main.rs` | `lib/gnome_podcasts.rb` / bin entrypoint | entrypoint | ✅ |
| `resources/gtk/secondary_menu.ui` ("Mark All Episodes as Played" / "Website" / "Unsubscribe" menu) | — (folded into `lib/show_menu.rb`) | menu | ⚠️ — `show_menu.rb` documents that this upstream `.ui` is not ported as its own file; it reimplements the same three items as `ShowMenu`'s action list instead. No gap in behavior, but no 1:1 file. |
| `resources/gtk/shortcuts-dialog.ui` | `lib/shortcuts_dialog.rb` | dialog | ✅ |
| `podcasts-gtk/src/widgets/aboutdialog.rs` | `lib/about_dialog.rb` | dialog | ✅ |

## Content / navigation

| Upstream | → lib/*.rb | Kind | Exists? |
|---|---|---|---|
| `widgets/content_stack.rs` | `lib/content_stack.rb` | stack/page-switcher | ✅ |
| `widgets/home_view.rs` + `resources/gtk/home_view.ui`, `home_episode_list.ui` | `lib/home_view.rb`, `lib/home_episode_list.rb` | page | ✅ |
| `widgets/shows_view.rs` | `lib/shows_view.rb` | page | ✅ |
| `widgets/queue_view.rs` + `resources/gtk/queue_view.ui` | `lib/queue_view.rb` | page | ✅ |
| `widgets/empty_view.rs` + `resources/gtk/empty_view.ui` | `lib/empty_view.rb` | empty state | ✅ |
| `widgets/empty_show.rs` + `resources/gtk/empty_show.ui` | `lib/empty_show.rb` | empty state | ✅ |
| `widgets/base_view.rs` | `lib/base_view.rb` | mixin/base | ✅ |
| `widgets/filter_menu.rs` + `resources/gtk/filter_menu.ui` | `lib/filter_menu.rb` | menu | ✅ |
| `src/widgets/mod.rs` → `main_menu` (hamburger model; built inline in `window.rs`, no standalone file upstream) | `lib/main_menu.rb` | menu | ✅ |

## Discovery

| Upstream | → lib/*.rb | Kind | Exists? |
|---|---|---|---|
| `widgets/discovery_page.rs` + `resources/gtk/discovery_page.ui` | `lib/discovery_page.rb` | page | ✅ |
| `widgets/discovery_search_results.rs` + `.../discovery_search_results.ui` | `lib/discovery_search_results.rb` | page | ✅ |
| `resources/gtk/discovery_found_podcast.ui` (`PdDiscoveryFoundPodcast`, `AdwPreferencesRow`) | `lib/discovery_found_podcast.rb` | row | ✅ |
| `podcasts-data/src/discovery/{mod,data,fyyd,itunes,search}.rs` | `lib/discovery.rb` | service/model | ✅ |

## Show / episode

| Upstream | → lib/*.rb | Kind | Exists? |
|---|---|---|---|
| `widgets/show.rs` + `resources/gtk/show_widget.ui` | `lib/show_widget.rb` | page/widget | ✅ |
| `podcasts-data/src/models/show.rs`, `new_show.rs` | `lib/show.rb` | model | ✅ |
| `widgets/show_menu.rs` + `resources/gtk/show_menu.ui` | `lib/show_menu.rb` | menu | ✅ |
| `widgets/episode.rs` + `resources/gtk/episode_widget.ui` | `lib/episode_widget.rb` | row | ✅ |
| `podcasts-data/src/models/episode.rs`, `new_episode.rs` | `lib/episode.rb` | model | ✅ |
| `widgets/episode_description.rs` + `.../episode_description.ui` | `lib/episode_description.rb` | page | ✅ |
| `podcasts-gtk/src/episode_description_parser.rs` | `lib/episode_description_parser.rb` | parser | ✅ |
| `widgets/episode_menu.rs` + `.../episode_menu.ui` | `lib/episode_menu.rb` | menu | ✅ |
| `widgets/read_more_label.rs` | `lib/read_more_label.rb` | widget | ✅ |
| `widgets/download_progress_bar.rs` | `lib/download_progress.rb` | widget | ✅ |
| `podcasts-gtk/src/chapter_parser/{mod,id3,extended_comment}.rs` | `lib/chapter_parser.rb` | parser | ✅ |
| `widgets/chapters.rs` + `resources/gtk/chapters.ui` (`PdChapters`, chapter list shown under an episode/player) | `lib/chapters.rb` | widget | ❌ missing |

## Player (entire subsystem)

| Upstream | → lib/*.rb | Kind | Exists? |
|---|---|---|---|
| `podcasts-gtk/src/player.rs` (the `Player`/`PlayerExt`/`PlayerUi` GStreamer playback object) | `lib/player.rb` | service | ❌ missing — `main_window.rb`'s own doc comment names this file and says the player actions (`win.play`, `win.pause`, `win.toggle-pause`, `win.seek-*`, `win.set-rate`, `win.raise/lower-playback-rate`, `win.close-bottom-sheet`) are intentionally not installed until it lands |
| `podcasts-gtk/src/player_mpris.rs` | `lib/player_mpris.rb` | service | ❌ missing (MPRIS media-key/shell integration) |
| `widgets/player_wrapper.rs` + `resources/gtk/player_wrapper.ui` (`PdPlayerWrapper`, `AdwBin`) | `lib/player_wrapper.rb` | widget | ❌ missing |
| `widgets/player_big.rs` + `.../player_big.ui` (`PdPlayerBig`, `GtkBox`) | `lib/player_big.rb` | widget | ❌ missing |
| `widgets/player_small.rs` + `.../player_small.ui` (`PdPlayerSmall`, `GtkBox`) | `lib/player_small.rb` | widget | ❌ missing |
| `widgets/player_rate.rs` + `.../player_rate.ui` (`PdPlayerRate`, `AdwBin`) | `lib/player_rate.rb` | widget | ❌ missing |
| `widgets/sheet_base.rs` + `.../sheet_base.ui` (`PdSheetBase`, `AdwBin`) | `lib/sheet_base.rb` | widget | ❌ missing |
| `widgets/sheet_description.rs` + `.../sheet_description.ui` (`PdSheetDescription`, `AdwBin`) | `lib/sheet_description.rb` | widget | ❌ missing |
| `widgets/sheet_player.rs` + `.../sheet_player.ui` (`PdSheetPlayer`, `AdwBin`) | `lib/sheet_player.rb` | widget | ❌ missing |
| `podcasts-gtk/src/thumbnail_generator.rs` (cover art used by the player as well as rows) | `lib/thumbnail_generator.rb` | service | ✅ |

This is the single biggest gap: the entire playback UI (mini player, full
player, speed-rate control, the bottom sheet and its description tab) plus
the GStreamer-backed `Player` object and MPRIS integration are absent. This
is also exactly where `gstreamer_play` (`GstPlay`) belongs. Checked the
wiring directly: the gemspec declares `spec.add_dependency("gstreamer_play")`,
and `lib/chapter_parser.rb` does `require "gstreamer_play"` — so the gem is
present and required, satisfying the letter of "required somewhere under
`lib/`". But read what it is used for: the comment there says the require
exists only to trigger `gstreamer_play`'s `gst_init` side effect before
`chapter_parser.rb` loads the bare `Gst`/`GstPbutils` namespaces itself for
chapter-tag discovery. Nothing under `lib/` touches the `GstPlay` namespace
itself — no playback, no pipeline, no URI being played. `lib/pipeline.rb` is
unrelated (it is upstream's feed-fetch pipeline, `podcasts-data/src/pipeline.rs`,
not playback). So today the gem is wired but its actual purpose — GstPlay-backed
episode playback — is unused, because the player component it belongs to
(`lib/player.rb`) does not exist yet. This is not a regression (the require is
legitimate and doing real work for the chapter parser), but it means
"check it still holds" is only half-true: required — yes; the namespace it
exists for — not yet exercised. Building `lib/player.rb` is what should
finally call `GstPlay` for real.

## Preferences / sync

| Upstream | → lib/*.rb | Kind | Exists? |
|---|---|---|---|
| `widgets/sync_preferences.rs` + `resources/gtk/sync_preferences.ui` (`PdSyncPreferences`, `AdwNavigationPage`, Nextcloud login/logout) | `lib/sync_preferences.rb` | page | ❌ missing — `main_window.rb` names `win.goto-sync-preferences` as withheld until this file lands |
| `podcasts-data/src/nextcloud_sync/{mod,data,login,upload,download}.rs` | `lib/nextcloud_sync.rb` | service | ❌ missing |
| `podcasts-data/src/models/sync/{mod,episode,show,settings}.rs` | folded into `lib/feed.rb`/`lib/episode.rb`/new file | model | ❌ missing |
| `podcasts-data/src/models/discovery_settings.rs` | `lib/discovery.rb` or `lib/settings.rb` | model | ❌ missing (no discovery-settings persistence seen in `lib/settings.rb`) |

## Downloads / data layer

| Upstream | → lib/*.rb | Kind | Exists? |
|---|---|---|---|
| `podcasts-gtk/src/manager.rs` (active-download tracking, `DownloadProgress`) | `lib/download_manager.rb` | service | ✅ |
| `podcasts-gtk/src/download_covers.rs` | `lib/download_covers.rb` | service | ✅ |
| `podcasts-data/src/downloader.rs` | `lib/download_manager.rb` / `lib/http.rb` | service | ✅ |
| `podcasts-data/src/database.rs`, `schema.rs`, `schema.patch` | `lib/database.rb` | data | ✅ |
| `podcasts-data/src/dbqueries.rs` | `lib/dbqueries.rb` | data | ✅ |
| `podcasts-data/src/feed.rs`, `feed_manager.rs` | `lib/feed.rb`, `lib/feed_manager.rb` | data/service | ✅ |
| `podcasts-data/src/parser.rs` | `lib/parser.rb` | parser | ✅ |
| `podcasts-data/src/xml` parsing (via `parser.rs`) | `lib/xml_parser.rb` | parser | ✅ |
| `podcasts-data/src/opml.rs` | `lib/opml.rb` | data | ✅ + `lib/opml_dialogs.rb` for the UI half |
| `podcasts-data/src/models/source.rs`, `new_source.rs` | `lib/source.rb` | model | ✅ |
| `podcasts-data/src/models/queue_item.rs`, `new_queue_item.rs` | `lib/queue_item.rb` | model | ✅ |
| `podcasts-data/src/http.rs` | `lib/http.rb` | service | ✅ |
| `podcasts-data/src/errors.rs` | `lib/errors.rb` | errors | ✅ |
| `podcasts-data/src/utils.rs` | `lib/data_utils.rb` | util | ✅ |
| `podcasts-gtk/src/utils.rs` | `lib/utils.rb` | util | ✅ |
| `podcasts-gtk/src/settings.rs` + `resources/org.gnome.Podcasts.gschema.xml.in` | `lib/settings.rb` | settings | ✅ — covers `persist-window-geometry-*`, `refresh-interval*`, `refresh-on-startup`, `cleanup-age-*`. No Nextcloud-sync keys exist upstream in this schema file to port (sync credentials/settings live in `models/sync/settings.rs`, which is itself unported). |
| `podcasts-gtk/resources/gtk/style.css` | `lib/style.rb` | stylesheet | ✅ |
| icon resources (`resources/icons/**`) | n/a (assets, not code) | assets | n/a |
| `resources/org.gnome.Podcasts.metainfo.xml.in.in`, `.desktop.in.in`, `.service.in` | packaging, not `lib/` | metadata | n/a — not a `lib/*.rb` component |
| `podcasts-gtk/po/*.po`, `LINGUAS`, `POTFILES.in` | translation catalogue | i18n | not assessed for parity here (see `translation-parity` skill) — flagged as present upstream (62 locales) with no evidence yet that `ruby`'s strings are marked for translation at all (no `gettext`/`_(...)` calls seen in the `lib/` files read this pass) |

## Summary

- **lib/ files present:** 43, covering essentially all of the non-player,
  non-sync surface: window, navigation, discovery, shows/episodes, menus,
  downloads, parsing, and the data layer.
- **Entirely missing subsystem #1 — Player.** 9 files
  (`player.rb`, `player_mpris.rb`, `player_wrapper.rb`, `player_big.rb`,
  `player_small.rb`, `player_rate.rb`, `sheet_base.rb`, `sheet_description.rb`,
  `sheet_player.rb`) plus `chapters.rb`. This is the component that should
  bring in `gstreamer_play`/`GstPlay` (and `GstBadAudio`); nothing in `lib/`
  requires it today, which is correct only because the player does not exist
  yet, not because the app has no use for it.
- **Entirely missing subsystem #2 — Nextcloud sync.** `sync_preferences.rb`,
  `nextcloud_sync.rb`, and the sync-specific data models. `win.goto-sync-preferences`
  is explicitly withheld pending this.
- Both gaps are already self-documented in `lib/main_window.rb`'s class
  comment, so this inventory confirms rather than discovers the two missing
  subsystems, and additionally catches the standalone `chapters.rb` and
  `discovery_settings.rs` model as not yet named anywhere.
- i18n: translation parity not evaluated in depth this pass; flagged for the
  `translation-parity` skill.

No app/widget code was written in this pass, per instructions.
