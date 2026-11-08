# Component identification — gnome-podcasts-rb (audit pass)

| | |
|---|---|
| Upstream | `origin/main` @ `35d671f6` (GNOME Podcasts, Rust + gtk-rs; unchanged since the prior audit pass) |
| Port | `ruby` branch, HEAD `c1050e6e` (re-run this pass; the prior pass at `4b0942a4` is superseded below) |
| Method | this report (prior pass, written against `4b0942a4`) re-walked against the **current** `lib/` tree and `origin/main`'s file list |

**Delta since the prior pass (`4b0942a4` → `c1050e6e`):** one new commit,
`c1050e6e` "Port the Nextcloud sync delta-tracking models", adds
`lib/models/sync.rb` (240 lines: `Sync::Episode`, `Sync::Show`,
`Sync::Settings`, `Sync.delete_deltas`). This is the **data model** half of
upstream's `podcasts-data/src/models/sync/{mod,episode,settings,show}.rs`
only. It does not touch, and does not reduce, any row in the "still entirely
absent" table below — the network/protocol half
(`podcasts-data/src/nextcloud_sync/*`, 5 files) and the whole UI half
(`sync_preferences.rs`/`.ui`, the menu item, the player subsystem) remain
exactly as absent as the prior pass found them. The keyring-backed password
storage inside upstream's `Settings` (`store`/`fetch`/`remove`, reading the
Secret Service over D-Bus) is explicitly left out of the port and documented
as such in `lib/models/sync.rb`'s header comment — an honest scope cut, not a
hidden one, and noted as such in `.reports/accountability-ensurance.md`.

The repo already carries a thorough, per-file component inventory at
`.reports/component-inventory.md`. It is honest in tone (it states blockers
rather than hiding them) but it is **stale**: its last writing commit is
`a49a24b2`, and three later commits changed the facts it reports on without
it being regenerated:

- `0c41aa38` (after the inventory, partially reflected) and `6909fa52`
  "Port the chapter parser and the episode description page" — `lib/chapter_parser.rb`
  (228 lines) and `lib/episode_description.rb` (389 lines) now **exist**. The
  inventory's tables at lines 223 and 465 still say `no` / "unported" for
  both.
- `5f864ce2` "Wire in gstreamer_play, gtk4, adwaita and glib2 as runtime
  dependencies" — the inventory's **Blocker 1** ("No GStreamer binding in the
  dev shell... `require "gst"` raises `LoadError`") is now **false**. Verified
  live in this audit:

  ```
  $ nix develop --command ruby -e 'require "gstreamer_play"; puts "ok"'
  ok
  ```

  `gstreamer_play` and the raw `Gst`/`GstPbutils` GI namespaces (which
  `lib/chapter_parser.rb` itself loads, see its header comment) are both
  reachable in the dev shell today. The stated reason the player, MPRIS and
  the `AdwBottomSheet` half of `main_window.rb` were not built no longer
  holds, and nothing has been rebuilt as a result.
- Drag-and-drop queue reordering, listed in the inventory as **Blocker 5**
  ("needs `Gtk::DragSource`/`DropTarget` wiring the pilot does not
  demonstrate... The queue rows exist... the reordering does not") is also
  now resolved: `lib/episode_widget.rb:474-510` installs a `Gtk::DragSource`
  and a `Gtk::DropTarget` (`init_drag_and_drop`, `drag_source`, `drag_end`).

These three corrections matter for this audit because they move the
project's own account of *why* work is missing. Two of the five stated
blockers for the single largest gap (the player) have quietly expired and the
gap itself has not been revisited. See `.reports/accountability-ensurance.md`.

## Current count

`lib/*.rb`: **52** files (51 at the prior pass, plus `lib/models/sync.rb`
landed in `c1050e6e`).

## What is present vs. absent, re-verified against `origin/main`'s file list

Verified directly (`git ls-tree -r --name-only origin/main`, `grep` over
`lib/`), not re-derived from the stale document:

### Present (confirmed built, not just claimed)

Everything the inventory's "Present" section lists, **plus**:
- `lib/chapter_parser.rb` — ported from `podcasts-gtk/src/chapter_parser/{mod,id3,extended_comment}.rs`. Loads `Gst`/`GstPbutils` GI namespaces directly since neither `gstreamer_play` nor any other fork gem exposes them.
- `lib/episode_description.rb` — ported from `src/widgets/episode_description.rs` + `episode_description.ui`.
- `Gtk::DragSource`/`Gtk::DropTarget` wiring in `lib/episode_widget.rb` for queue reordering.
- `lib/models/sync.rb` (new this pass) — ported from `podcasts-data/src/models/sync/{mod,episode,settings,show}.rs`. Data model only: three new JSON-store tables with upstream's upsert-on-conflict keys and the stale-Play-action ignore rule. No network sync, no UI, no keyring (documented cut).

### Still entirely absent — re-verified by `grep -ril "player|mpris|sheet_player|sync_pref" lib/ exe/`, which returns **zero** files other than files that match the word "player" only inside prose comments explaining the gap

| Upstream file | Port file that should exist | Exists |
|---|---|---|
| `src/player.rs` | `lib/player.rb` | **no** |
| `src/player_mpris.rs` | `lib/player_mpris.rb` | **no** |
| `src/widgets/player_wrapper.rs` + `.ui` | `lib/player_wrapper.rb` | **no** |
| `src/widgets/player_big.rs` + `.ui` | `lib/player_big.rb` | **no** |
| `src/widgets/player_small.rs` + `.ui` | `lib/player_small.rb` | **no** |
| `src/widgets/player_rate.rs` + `.ui` | `lib/player_rate.rb` | **no** |
| `src/widgets/sheet_base.rs` + `.ui` | `lib/sheet_base.rb` | **no** |
| `src/widgets/sheet_player.rs` + `.ui` | `lib/sheet_player.rb` | **no** |
| `src/widgets/sheet_description.rs` + `.ui` | `lib/sheet_description.rb` | **no** |
| `src/widgets/chapters.rs` + `.ui` (the chapters *list page*; distinct from the chapter *parser*, which is ported) | `lib/chapters.rb` | **no** |
| `src/widgets/sync_preferences.rs` + `.ui` | `lib/sync_preferences.rb` | **no** |
| `src/nextcloud_sync/{mod,data,download,login,upload}.rs` (the Nextcloud HTTP protocol: login, upload/download deltas) | none | **no** — unchanged this pass |
| `src/models/sync/{mod,episode,show,settings}.rs` | `lib/models/sync.rb` | **yes, new this pass** — data model only; see delta note above |
| `podcasts-gtk/po/*.po` (45 locales) + `POTFILES.in` | `po/` + gettext wiring | **no** — see `.reports/translation-parity.md` |
| `podcasts-gtk/resources/org.gnome.Podcasts.gschema.xml.in` UI surface, `.desktop.in.in`, `.metainfo.xml.in.in` | none in the port | **no** — only the 8 keys with no upstream UI are read (`lib/settings.rb`); the app has no `.desktop`/metainfo/schema files of its own |

### Component the port removes an entry point for, confirmed by reading the menu source

`lib/main_menu.rb` (51 lines, read in full) builds exactly two sections —
`FEED_SECTION` (`win.refresh`, `win.import`, `win.export`) and `APP_SECTION`
(`app.shortcuts`, `win.about`). Upstream's hamburger menu (recorded in the
existing inventory, `window.ui`) also has **"Sync Preferences" →
`win.goto-sync-preferences`**, placed between the feed section and the
shortcuts/about section. The port's menu has no such item and `main_window.rb`
installs no `win.goto-sync-preferences` action (confirmed by `grep`). This is
not merely "the sync preferences page doesn't exist" — the port's menu model
itself was built with one fewer row than upstream's, silently.

### Blockers that remain real, re-checked

- **MPRIS / `Gio::DBus` desktop integration** (`player_mpris.rs`): no
  established pattern in the pilot port (`gnome-contacts-rb`), still true.
- **Nextcloud sync** (`src/nextcloud_sync/`): the HTTP protocol layer
  (login, upload/download of deltas — 5 files, 22 upstream tests, see
  `.reports/test-parity.md`) is still absent. The **data model** half
  (`src/models/sync/`) landed this pass as `lib/models/sync.rb`, so this
  blocker has narrowed — but `sync_preferences.rb` still cannot be
  meaningfully built without the protocol layer it displays the state of,
  and the menu item it would hang off (`win.goto-sync-preferences`) is
  still not installed.

## Scope note

This pass re-verifies and corrects the existing inventory rather than
re-running `component-scan.sh`/`gir-symbols.sh` from a clean slate; the
per-widget, per-signal, per-CSS-class tables already in
`.reports/component-inventory.md` for the **present** files were spot-checked
against the files named (`lib/main_window.rb`, `lib/episode_widget.rb`,
`lib/show_menu.rb`, `lib/main_menu.rb`) and found accurate for what they
describe. The corrections above are the material that document was missing.
See `.reports/component-parity.md` for the four-axis comparison on the units
this identification pass flags as the live gaps.
