# Accountability ensurance — gnome-podcasts-rb

Scope grepped: `lib/`, `exe/`, `.reports/`. `PORTING.md` does not exist on
this branch (`ls PORTING.md` → No such file or directory) — there is no
authority document to check against a parity ledger, which is itself worth
recording: nothing in this repo claims the authority the skill warns about,
which narrows this report to code comments and the inventory report.

## Keyword scan (`TODO`, `FIXME`, `not implemented`, `for now`, `in a future`, `not yet`, `stub`, `placeholder`)

```
$ grep -rniE "TODO|FIXME|not implemented|for now|in a future|not yet implemented" lib/ exe/ .reports/
(no matches)
```

No hits. The port carries none of the toothless labels the skill flags —
that is a real, separate fact worth stating rather than silently absorbing
into "clean": it means the serious finding below is not a labelled TODO
anyone could grep for and fix. It is structural.

## Excuse-pattern scan (`find-excuses.sh`)

Re-run this pass (`c1050e6e`, one commit after the prior pass's `4b0942a4`):

```
.reports/component-inventory.md:162  "deliberately skipped" / "n/a" / "not ported" / "skipped"
.reports/component-inventory.md:443   "unported"
.reports/component-inventory.md:465   "unported"
lib/show_menu.rb:15                   "not ported"
lib/source.rb:77                      "not required here"
lib/models/sync.rb:163                "not ported"  — NEW this pass, lands with lib/models/sync.rb
```

Each one read in context, individually:

1. **`component-inventory.md:162` / `lib/show_menu.rb:15` — "not ported",
   "deliberately skipped", "n/a".** Both refer to the same fact:
   `secondary_menu.ui` has all three `action=` attributes commented out in
   `origin/main`'s own source, confirmed by reading it — it is dead code
   upstream, its items having moved elsewhere. **This is a false positive of
   the scan, not an excuse.** The skill is explicit that a correspondence
   named and located is not a gap; this one is named (`lib/show_menu.rb:15`)
   and verifiably true against upstream. No rewrite needed. Recording this
   rather than silently dropping it, because the scan found it and a lazier
   audit would have reported it as a violation without checking.

2. **`lib/source.rb:77` — "not required here".** Reads "`feed` is not
   required here: it requires this file in turn, and the callers that fetch
   a feed load it" — this is about Ruby `require` load order, not a feature
   decision. **False positive.** Not an excuse; nothing is missing.

3. **`component-inventory.md:443` / `:465` — "unported".** These are the
   report's own Blocker 3 (Nextcloud sync) and Dialogs table entries. Plain,
   first-person-adjacent factual statements naming the missing component and
   the files affected — closer to the skill's required style ("name the
   behaviour") than to an excuse, though not phrased as an admission. Left
   as a **minor finding**: these two lines should be rewritten in the
   skill's register, because right now they read as a status update rather
   than a debt. Not escalated further because they do not launder the gap —
   the gap is listed, with files, elsewhere in the same document, repeatedly.

4. **`lib/models/sync.rb:163` — "See the module comment above for what is
   not ported here" (new this pass).** The module comment it points to
   (`lib/models/sync.rb:17-25`) names the specific omission plainly:
   upstream's `Settings::store`/`::fetch`/`::remove` read and write the
   sync password through the desktop keyring (`oo7::Keyring`, Secret
   Service over D-Bus); this port has no secret-storage gem in its
   dependency list (confirmed: `grep -i "keyring\|secret" *.gemspec` and
   `gem list` in the dev shell both return nothing), and declines to
   hand-roll a raw `Gio::DBusProxy` Secret Service client as a workaround.
   This names the behaviour (password storage) and the reason (no gem),
   which is most of what the skill asks for — it falls short only in
   register, reading as a calm scope note rather than a first-person debt.
   **Minor finding, same bucket as #3**: low stakes right now because the
   page that would call these methods (`sync_preferences.rb`) does not
   exist yet and is already tracked as a full gap elsewhere in this round's
   reports — but the phrasing should still be rewritten before
   `sync_preferences.rb` is built, so the keyring omission does not quietly
   outlive the reason it is currently true for.

None of these six scan hits is the real problem. **Three other things in
the repository are**, and none of them was caught by the keyword list,
because they are not phrased as excuses — they are phrased as settled plans
and settled facts, which is the more dangerous version of the same failure.

## Finding 1 (serious) — a false-green test claim with zero backing

`.reports/component-inventory.md:226`:

> `episode_description_parser.rb` (ported in commit `0c41aa38`): passes all
> 13 of upstream's own test cases byte for byte, including two intentional
> oddities of upstream's output that a comment at the top of the file
> explains are kept on purpose.

Checked directly:

```
$ grep -rl "episode_description_parser" spec/
(no output)
$ ls spec/
chapter_parser_spec.rb  data_layer_spec.rb  spec_helper.rb  README.md
```

There is no spec file for `episode_description_parser.rb` anywhere in the
repository, and the rspec suite (20 examples, verified running in this
audit — see `.reports/test-parity.md`) contains none of upstream's 13 cases
for this file. **"Passes all 13 of upstream's own test cases" is not true in
any mechanically checkable sense — it cannot be, because no test exists to
run them.** At best this sentence records a one-time manual comparison the
writer did and did not preserve as a test; at worst it is invented. Either
way, a reader of the inventory — including the next agent that picks up
this port — has no way to tell the difference, and the sentence is written
with exactly the confidence of a passing CI badge.

This is the single most serious finding in this audit, per the task's own
framing: **a false green claim in a report, resting on something never
executed.** It is not hidden behind an excuse keyword; it reads as a
completed, verified fact.

What is owed: `spec/episode_description_parser_spec.rb`, one `it` per
upstream case (13), each asserting the exact byte output upstream's own
test fixtures assert, including the two named "intentional oddities." Until
that file exists, the sentence above should be corrected to state plainly
that the claim is unverified.

**Update, this round:** `spec/episode_description_parser_spec.rb` now exists,
with all 13 `it` blocks named after upstream's 13 `#[test] fn`s, each
carrying upstream's own `description`/`expected` fixture strings verbatim.
Run live:

```
$ nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "documentation", "--require", "spec_helper", "spec/episode_description_parser_spec.rb"])'
13 examples, 0 failures
```

The claim in `component-inventory.md:226` is corrected to point at this file
instead of asserting the number with nothing behind it. Finding 1 is closed
by the spec existing and passing, not by softer wording.

## Finding 2 — two of five stated blockers for the single biggest gap have silently expired

`.reports/component-inventory.md`'s "Blockers" section (written at commit
`a49a24b2`) gives, as **Blocker 1**, the reason the entire player stack (10
files), the `AdwBottomSheet`/`AdwMultiLayoutView` half of `main_window.rb`,
and the Player section of `shortcuts_dialog.rb` are unbuilt:

> **No GStreamer binding in the dev shell.** `require "gst"` raises
> `LoadError`... audio parity is blocked until the flake provides a `gst`
> gem.

Checked live in this audit, in the fork's own dev shell:

```
$ nix develop --command ruby -e 'require "gstreamer_play"; puts "ok"; require "gobject-introspection"; puts "ok"'
ok
ok
```

Commit `5f864ce2`, titled "Wire in gstreamer_play, gtk4, adwaita and glib2 as
runtime dependencies," landed **after** the inventory that states this
blocker, and `lib/chapter_parser.rb` itself (ported in commit `6909fa52`,
also after the inventory) already loads `Gst`/`GstPbutils` as raw GI
namespaces successfully, by its own header comment. **The stated reason the
player cannot be built is no longer true, and the player still has not been
built, and nothing records that the reason expired.** A reader of the
inventory today inherits a blocker that reads as live and is not. That is
exactly the mechanism this skill exists to catch: a note that was once an
honest statement of fact has, through the passage of two unrelated commits,
become a statement that lets a real, closeable gap keep reading as blocked.

Separately, **Blocker 5** ("Drag-and-drop queue reordering... needs
`Gtk::DragSource`/`DropTarget` wiring the pilot does not demonstrate") is
also now false — `lib/episode_widget.rb:474-510` builds exactly that wiring.
This one is lower stakes (it is resolved, not merely stale), but it is the
same failure in miniature: the inventory was not updated when the work
landed, so a correctly-closed gap still reads as open, which is the opposite
error but comes from the same root cause — a stale document being trusted
instead of re-verified.

What is owed: regenerate `.reports/component-inventory.md`'s Blockers
section against the current tree (this audit's
`.reports/component-identification.md` does this), and — separately and
more importantly — **actually build the player** now that its stated
blocker is gone. The gap is the same size it was before `5f864ce2` landed;
only the excuse for it has quietly disappeared.

**Update, this round:** the Blockers section has been regenerated against
the current tree, and the attempt to actually build the player surfaced
that "the stated reason the player cannot be built is no longer true" was
only half right. `require "gstreamer_play"` does succeed, as this finding
says — but `GstPlay::Play.new`, the one call every player design needs
first, crashes the Ruby process with a deterministic SIGSEGV (3/3 runs),
before any uri or config is touched. The root cause: GstPlay builds
`playbin3` on its own GLib thread, gst-plugins-base 1.28.7 logs a
`GLib-GObject-CRITICAL` during that construction, and ruby-gnome's `glib2`
gem's global log handler tries to call back into the Ruby VM from that
thread, which the VM never registered and which segfaults unconditionally.
No handler-level workaround avoided it. `component-inventory.md`'s Blockers
section now states this as the current, still-open reason instead of
repeating the resolved-sounding old one. The player stack was not built
this round because of this, not because of the old GStreamer-availability
reason, which really is gone. See this round's result `notes` /
`gems_unusable` for the exact repro.

## Finding 3 — the player's absence is recorded as a forward plan, not a debt

`lib/main_window.rb:28-31`:

> Upstream's actions that need components the port has not reached yet are
> not installed rather than installed as actions that would do nothing: the
> player ones (win.play, win.pause, win.toggle-pause, win.seek-*,
> win.set-rate, win.raise/lower-playback-rate, win.close-bottom-sheet)
> arrive with lib/player.rb, and win.goto-sync-preferences with
> lib/sync_preferences.rb.

`lib/episode_widget.rb:26-27`:

> The two states that need a player, Playing and Playable's play button, are
> left out until lib/player.rb exists rather than shown as buttons that
> would do nothing.

`lib/shortcuts_dialog.rb:14-15`:

> listed as shortcuts that do nothing: the Player section arrives with...

None of these three sentences matches the keyword scan — there is no
"TODO," no "not implemented," no "n/a." Each is written as engineering
reasoning for a design choice (don't wire a dead button) that is itself
sound. But all three share the same shape the skill names directly: a
confident forward reference ("arrives with lib/player.rb") that reads as a
scheduled, known next step rather than as nine files of behaviour nobody has
built, with its one stated precondition (GStreamer availability) already
gone per Finding 2. A reader meets a plausible, calm explanation and moves
on — which is the entire mechanism this skill exists to interrupt. These are
not catalogued anywhere as an owed, user-facing behaviour ("the person
cannot play a podcast in this app") — they are catalogued as a file that
does not exist yet.

This finding is reported in the terms the skill actually sets, not
softened: the port plays no audio, shows no playback UI, exposes no MPRIS
controls to the desktop environment, and the three sentences above are the
closest thing in the codebase to an explanation, and the explanation is
calm. Per the skill's own worked example from `console-rb`, the fix is not
to add a label — it is to say, plainly, what a person opening this app
cannot do: **play, pause, seek, or see the current chapter of a podcast
episode**, in an app whose entire purpose is listening to podcasts.

## What this audit did not find

- No hit for "by design," "out of scope," "modernised away," "upstream's own
  TODO," or "the bindings do not support it" anywhere in `lib/`, `exe/`, or
  `.reports/`.
- No evidence the 97/97 drive gate or 20/20 rspec gate is itself
  misrepresented — both were re-run live in this audit (see
  `.reports/test-parity.md`) and both numbers hold. The gate is real; it is
  simply narrow, and the existing `.reports/component-inventory.md` does not
  claim otherwise anywhere this audit found.

## Verdict

Not clean. One false-green claim with zero test backing (Finding 1, the most
serious category this audit can report), one expired blocker still gating
the single largest functional gap in the app without anyone noticing it
expired (Finding 2), and the player's absence recorded throughout the
codebase as a forward plan rather than as the missing core function of a
podcast player (Finding 3). The keyword/excuse scans themselves came back
almost clean — which is precisely why Findings 1–3 matter more than a longer
list of "for now"s would have: the dangerous material here reads as
competent, calm, and done.

**This pass (`c1050e6e`):** one new commit since the prior pass, adding
`lib/models/sync.rb`. It introduces one new minor scan hit (#4 above, the
keyring omission), correctly explained rather than laundered, and does not
touch or resolve Findings 1–3 — the player is still absent, the GstPlay
segfault blocker from Finding 2 was not re-tested this pass and is assumed
unchanged, and `lib/main_window.rb`/`lib/episode_widget.rb`/
`lib/shortcuts_dialog.rb` still carry the same "arrives with lib/player.rb"
forward-reference language Finding 3 names. The new commit is honestly
scoped and does not change the verdict.
