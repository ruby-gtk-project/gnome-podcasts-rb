# Translation parity — gnome-podcasts-rb

| | |
|---|---|
| Upstream | `main` @ `35d671f6` (unchanged since the prior pass) |
| Port | `ruby` @ `c1050e6e` (re-run this pass; prior pass was `4b0942a4`) |
| Domain | `gnome-podcasts` (upstream's `.mo`/project name — not independently reconfirmed via `meson.build` in this pass; see Open) |
| Upstream messages | **178** distinct `msgid`s (counted from `podcasts-gtk/po/fr.po`, `grep -c '^msgid "'`; one of these is the empty header entry, so **177** real messages) |
| Ported | **0** |
| Gaps | **177** |
| Extra (untranslated) | 0 — the port has no marked strings of any kind |
| Upstream languages | **45** `.po` files under `podcasts-gtk/po/` |
| Languages shipped by the port | **0** |
| Build command | none — no gettext target exists |

## The finding, stated first because it is unambiguous

```
$ find lib/ exe/ -iname '*locale*'; grep -rl "gettext\|GETTEXT\|_(\"" lib/
(no output — both commands return nothing)
$ find . -iname '*.po' -not -path './.git/*'
(no output)
```

The port has **no `po/` directory, no gettext dependency in the Gemfile, no
`require "gettext"` anywhere, and not one string anywhere in `lib/` passed
through a translation marker.** Every one of the ~177 user-visible strings
the existing `.reports/component-inventory.md` catalogues as ported — "Marked
all episodes as listened", "Unsubscribed from {show}", every button label,
every menu item, every empty-state title — is a bare Ruby string literal.

This is not "translation not finished yet." Per the skill, there is no such
state: upstream ships 45 languages today, in this same repository, and the
port regresses all of them to English-only. That is the finding, in exactly
those terms.

## The three required claims, checked

1. **Key sets equal?** No. Upstream: 177 keys. Port: 0 keys (no marker
   exists to extract from). **177 gaps, 0 extra.**
2. **Byte-identical?** Vacuously fails — there is nothing on the port side to
   compare byte-for-byte.
3. **Languages ship?** No. 0 of 45 `.po` files exist in the port; nothing is
   compiled to `.mo`; nothing is bound with `bindtextdomain`.

## Upstream catalogue shape (for scoping the work still owed)

`podcasts-gtk/po/POTFILES.in` lists 55 source entries (23 `.ui` files plus
Rust sources). Representative high-use strings an eventual port would need
to carry byte-identical (spot-checked from `fr.po`, not exhaustively
censused in this pass — see Open):

- Button/menu labels already built as plain strings in the port today:
  `"Open Website"`, `"Mark All as Played"`, `"Unsubscribe"` (`lib/show_menu.rb`),
  `"_Check for New Episodes"`, `"_Import Shows"`, `"_Export Shows"`,
  `"_Keyboard Shortcuts"`, `"_About Podcasts"` (`lib/main_menu.rb`).
- Toast strings: `"Marked all episodes as listened"`,
  `"Unsubscribed from {}"` (format-interpolated — upstream's equivalent is a
  `gettext`/format call with the show name substituted *after* lookup; the
  port must not interpolate before marking, the exact trap the skill calls
  out: `"Unsubscribed from #{show.title}"` would be unrecoverable even if a
  marker were wrapped around it, because the key differs per show).
- Relative-time strings in `lib/utils.rb` (per the existing inventory,
  line ~421): "Just now", "{} minute(s) ago", "{} hour(s) ago", "{} day(s)
  ago", "{} month(s) ago", "{} year(s) ago" — these are **plural forms**
  upstream and must use `n_()`/`ngettext`, not a single string with manual
  pluralisation.

## Occurrences and reuse

Not independently re-censused per-call-site in this pass (would require the
skill's `msgid-census.sh`/`catalogue.rb` run against both trees). Flagged as
open rather than asserted.

## Why this matters more than the component/test gaps

Per the skill: a GNOME app's `po/` directory is donated human work that a
port cannot regenerate. Upstream's 45 languages represent translator effort
this port currently discards in full, silently — the app builds, runs, and
every drive check in `.reports/test-parity.md` passes, while shipping 0 of
45 languages. Nothing in the 97/97 drive-check gate or the 20/20 rspec gate
would ever surface this: both check English strings against English
expectations.

## Verdict

**0/177 messages, 0/45 languages. Parity is not close, not partial, not
"pending" — it has not been started.** No gettext gem, no `po/`, no markers.
This is the cleanest, least-arguable finding in this audit: there is nothing
to cross-check or interpret, only an absence to confirm, and it has been
confirmed directly.

## Open (work this report does not complete)

- A full per-message census (`msgid<TAB>kind<TAB>uses<TAB>sites`) against
  `podcasts-gtk/po/POTFILES.in`'s 55 source entries was not built in this
  pass; the 177 figure comes from one `.po` file's `msgid` count, not from
  the skill's `catalogue.rb`/`msgid-census.sh` tooling run against source.
  Treat 177 as a solid estimate, not the generated-and-verified number the
  skill's ledger format calls for.
- Confirm the `.mo` domain name against `podcasts-gtk/po/meson.build` /
  `GETTEXT_PACKAGE` before any port work starts, per the skill's warning that
  the project name and the domain can differ.
- Fuzzy/obsolete entry counts across the 45 `.po` files were not tallied.
