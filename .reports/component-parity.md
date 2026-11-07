# Component parity — gnome-podcasts-rb

| | |
|---|---|
| Upstream | `main` @ `origin/main` |
| Port | `ruby` @ `4b0942a4` |
| Units with full (4-axis) parity, of units attempted | see per-unit table below |
| Units upstream ships that the port has not started | **12** (player ×10, sync preferences, chapters page) |

Runtime gate for this round: `drive_ok=true`, 97/97 checks across
`test/drive_covers.rb` (19), `test/drive_discovery.rb` (38),
`test/drive_episode_description.rb` (3) and `test/drive_main_window.rb` (37),
re-run in this audit and confirmed green. **That gate exercises 4 of the ~20
upstream component groups.** It never opens the player, never opens the
sync-preferences page (because neither exists), never drives the show menu's
destructive actions to completion beyond the toast appearing, and never
drives the filter menu's "Downloaded" state. A component this gate does not
touch is **unverified**, not passing — see Rule below and
`.reports/accountability-ensurance.md` for the false-green risk this creates
if read the other way.

## Units compared

### Window menu — `src/window.rs`/`window.ui` → `lib/main_window.rb`, `lib/main_menu.rb`

| Item | Upstream | Port | Verdict |
|---|---|---|---|
| "Check for New Episodes" → `win.refresh` | yes | yes (`lib/main_menu.rb:14`) | parity |
| "Import Shows" → `win.import` | yes | yes (`:16`) | parity |
| "Export Shows" → `win.export` | yes | yes (`:18`) | parity |
| **"Sync Preferences" → `win.goto-sync-preferences`** | yes | **absent** — not in `FEED_SECTION`/`APP_SECTION` of `lib/main_menu.rb`, and `win.goto-sync-preferences` is not installed in `lib/main_window.rb` (`grep` confirms) | **gap** |
| "Keyboard Shortcuts" → `app.shortcuts` | yes | yes | parity |
| "About Podcasts" → `win.about` | yes | yes | parity |
| `Adw.MultiLayoutView` (`wide`/`narrow` layouts) | yes | **absent** (`main_window.rb` builds a plain toolbar view; no layout slots) | **gap** — exists only to host the player, per the port's own comment at `main_window.rb:28-31` |
| `Adw.BottomSheet` | yes | **absent** | **gap**, same reason |
| 2 player breakpoints (`min-width:800sp` applying the player, etc.) | yes | **absent** | **gap** |
| Actions `win.play`, `win.pause`, `win.toggle-pause`, `win.seek-forwards`, `win.seek-backwards`, `win.set-rate`, `win.raise/lower-playback-rate`, `win.close-bottom-sheet` | 8 actions | **0 installed** | **gap** — explicitly not installed, per the comment `main_window.rb:28-31` |
| Accelerators for the 8 player actions (`<primary>space`, `<primary>Right`, `<primary>Left`, `<primary>greater`, `<primary>less`, etc.) | 6 accelerators | **0** | **gap** |

### Shortcuts dialog — `shortcuts-dialog.ui` (no backing source) → `lib/shortcuts_dialog.rb`

| Section | Upstream items | Port items | Verdict |
|---|---:|---:|---|
| Navigation (4) | 4 | 4 | parity |
| Player (5: Toggle Pause, Seek Forwards, Seek Backwards, Raise/Lower Playback Speed) | 5 | **0** | **gap** |
| General (5) | 5 | 5 | parity |

9 of 14 upstream shortcut items exist in the port. The file's own header
comment (`lib/shortcuts_dialog.rb:8-15`) states the Player section "arrives
with" the player — see accountability report.

### Player stack — 10 upstream files → 0 port files

| Upstream | Kind | Port file | Verdict |
|---|---|---|---|
| `src/player.rs` | playback controller | — | **gap** (no widget axis applies — this is pure logic — but zero of play/pause/seek/rate/queue-advance behaviour exists anywhere in the port) |
| `src/player_mpris.rs` | MPRIS/D-Bus | — | **gap** |
| `src/widgets/player_wrapper.rs`+`.ui` | `Gtk.Stack` of big/small | — | **gap** |
| `src/widgets/player_big.rs`+`.ui` | rewind/play-pause/forward, `Gtk.Scale`, timer, `PdPlayerRate` | — | **gap** |
| `src/widgets/player_small.rs`+`.ui` | `Gtk.ProgressBar`, cover, play/pause | — | **gap** |
| `src/widgets/player_rate.rs`+`.ui` | 7-rate `Gtk.MenuButton` | — | **gap** |
| `src/widgets/sheet_base.rs`+`.ui` | bottom sheet shell, 3-page `Adw.ViewStack` | — | **gap** |
| `src/widgets/sheet_player.rs`+`.ui` | full-screen player page | — | **gap** |
| `src/widgets/sheet_description.rs`+`.ui` | description page in sheet | — | **gap** |
| `src/widgets/chapters.rs`+`.ui` | chapters list page | — | **gap** (the chapter *parser*, `lib/chapter_parser.rb`, is ported and unit-tested; the chapter *list UI* that would display what it parses is not) |

This is the single largest hole in the port: GNOME Podcasts' primary function
is playing audio, and no path in the Ruby port plays, pauses, seeks, shows
elapsed time, shows chapters, changes playback rate, or exposes MPRIS
controls to the desktop. `lib/download_manager.rb`/`lib/queue_item.rb` manage
*downloading and queueing* episodes; nothing consumes the queue into
playback.

### Sync preferences — `sync_preferences.rs`+`.ui` → `lib/sync_preferences.rb`

Entire page absent, plus its whole data layer (`src/nextcloud_sync/*`,
`src/models/sync/*`) absent. Zero widgets, zero of the two `Adw.ToggleGroup`
login modes, zero of the 5 loading-state strings.

### Units with full 4-axis parity on spot check

Re-checked against upstream source, not just the inventory's claim:

- **`show_menu.rs`+`.ui` → `lib/show_menu.rb`**: 3 actions
  (`show.open-website`, `show.mark-played`, `show.unsubscribe`), both
  destructive ones building an `Adw::Toast` with an Undo action and
  committing on dismiss — matches `lib/show_menu.rb` read in full. `parity`.
  `secondary_menu.ui` is correctly *not* ported — verified upstream's
  `resources/gtk/secondary_menu.ui` has all three `action=` attributes
  commented out, so it is dead code upstream; this is a correspondence, not a
  gap, and `lib/show_menu.rb`'s header comment names it correctly (not an
  excuse — see accountability report, this one hit was a false positive of
  the excuse-scan).
- **Episode drag-and-drop** (`episode_widget.ui`'s drop-target revealers,
  drag handle, drag icon): `lib/episode_widget.rb:168-182,472-510` builds the
  drag handle, a `Gtk::DragSource` and a `Gtk::DropTarget`, matching
  upstream's `init_drag_and_drop`. `parity` — this was recorded as a gap in
  the stale `.reports/component-inventory.md` (Blocker 5) and should be
  closed there too.

## Text axis

Every component above, whether built or not, fails the text axis for the
same underlying reason: see `.reports/translation-parity.md`. **0 of the
~178 upstream msgids are marked for translation anywhere in `lib/`.** Even
the units with full widget/CSS/behaviour parity (e.g. `show_menu.rb`'s toast
strings "Marked all episodes as listened", "Unsubscribed from {show}") are
plain Ruby string literals, not `_()`/`n_()` calls, so no unit in the port
can be marked `parity` on all four axes simultaneously. The per-unit
verdicts above are given on the widget/CSS/behaviour axes only, with text
tracked once, centrally, in the translation report rather than repeated on
every row.

## Verdict

**No parity.** The port has built roughly four-fifths of the non-player
surface (content views, discovery, episode rows/menus, empty states, OPML
import/export) with real behavioural fidelity where checked, but the app's
core function — audio playback — does not exist in any form, the sync
preferences surface does not exist, one menu item was dropped silently
without being recorded as a gap in the port's own menu file, and the text
axis fails for literally every string in the app.

## Rules applied

- Reported per-unit, not as an app-wide widget-type total (a count would
  hide the fact that a whole functional area — playback — is the one
  missing, not a scattering of individual rows).
- The 97/97 drive gate is reported as what it covers (4 units), not
  generalised into "the UI is verified."
