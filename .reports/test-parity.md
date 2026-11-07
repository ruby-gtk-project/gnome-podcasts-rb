# Test parity — gnome-podcasts-rb

| | |
|---|---|
| Upstream | `main` @ `35d671f6` (worktree pinned for this audit; record this sha) |
| Port | `ruby` @ `4b0942a4` |
| Upstream tests (census) | **123** (`scripts/test-census.sh`, cross-checked by hand against `#[test]` occurrences per file: 121 by hand-count, 123 by script — the 2-test discrepancy is `podcasts-gtk/src/utils.rs`, 7 by script vs 3 counted by eye; not resolved in this pass, see "Open" below) |
| Ported (named, bijective) | **0** confirmed by name. See "Why 0, not 20" below |
| Gaps | up to 123, pending the row-by-row census this report does not complete |
| Suite actually run | **yes** — both commands below were executed in this audit, not assumed |
| Test command | `nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'` → `20 examples, 0 failures` |
| Drive command | `nix develop --command xvfb-run -a ruby test/drive_*.rb` → `19+38+3+37 = 97 of 97 checks passed`, `DRIVE OK` on all four |

## What was actually run in this audit, and the result

Both commands above were executed live, not inferred from a prior claim:

```
Finished in 0.61691 seconds (files took 2.36 seconds to load)
20 examples, 0 failures
```

```
=== test/drive_covers.rb ===    19 of 19 checks passed   DRIVE OK
=== test/drive_discovery.rb === 38 of 38 checks passed   DRIVE OK
=== test/drive_episode_description.rb === 3 of 3 checks passed  DRIVE OK
=== test/drive_main_window.rb === 37 of 37 checks passed  DRIVE OK
```

This matches the runtime gate given for this round (97 checks, 20 components
claimed). **The gate itself is real and was reproduced, not just repeated
from a prior report.**

## Why that gate does not establish test parity

Test parity (per the skill) is a **bijection between upstream's named test
cases and the port's**, not a pass/fail count on the port's own suite. The
97 drive checks and the 20 rspec examples are **the port's own test design**
— none of them is named after, or asserts the identical property as, a
specific upstream `#[test]`. Census of upstream:

| Upstream file | Tests | Port counterpart censused? |
|---|---:|---|
| `podcasts-data/src/utils.rs` | 17 | partially — `spec/data_layer_spec.rb:252` ("formats the strings the episode rows print") asserts `format_duration`, `format_minutes`, `format_size` and `relative_time` all in **one** `it` block. Upstream pins these as separate `#[test]`s. **This is exactly the merge the skill forbids** ("Never merge two upstream tests into one Ruby test to save typing. The count is the check; collapsing rows disables it.") |
| `podcasts-gtk/src/episode_description_parser.rs` | 13 | **0** — no spec file exists for this file. See `.reports/accountability-ensurance.md`: the existing `.reports/component-inventory.md:226` claims this file "passes all 13 of upstream's own test cases byte for byte," and that claim has **no test backing it anywhere in the repo** (`grep -rl episode_description_parser spec/` returns nothing). This is a **false-green claim**, flagged as the most serious kind of finding this audit can make. |
| `podcasts-data/src/models/new_show.rs` | 10 | 0 named — `data_layer_spec.rb` has model-adjacent assertions inside `Feed`/`Dbqueries` `it` blocks, but no test is named after or isolated to `NewShow`'s own validated cases |
| `podcasts-data/src/models/new_episode.rs` | 10 | 0 named, same reasoning |
| `podcasts-data/src/feed.rs` | 8 | partially — `Feed` has 4 `it` blocks in `data_layer_spec.rb`, none named after a specific upstream case |
| `podcasts-data/src/models/show.rs` | 7 | 0 named |
| `podcasts-gtk/src/utils.rs` | 3–7 (script says 7, hand count says 3; unresolved) | 0 named |
| `podcasts-data/src/discovery/{itunes,fyyd,search}.rs` | 10 | **0** — `discovery.rb` has no spec file at all; only exercised indirectly by `test/drive_discovery.rb`'s thumbnail-scaling and cover-placement checks, which test the port's own thumbnail logic, not iTunes/fyyd query building or response parsing |
| `podcasts-data/src/nextcloud_sync/*` + `models/sync/*` | 23 | **0**, and cannot be ported until the component exists (see component reports) — these 23 are a permanent gap, not a deferred one, until `sync_preferences.rb`/the Nextcloud data layer is built |
| `podcasts-data/src/dbqueries.rs` | 3 | partially — `Dbqueries` has 5 `it` blocks covering filtering, queueing and removal; no 1:1 naming |
| `podcasts-data/src/opml.rs` | 2 | 2 `it` blocks exist (`reads the feed urls...`, `round-trips the subscriptions...`) and plausibly cover the same two upstream cases by behaviour, but are not named to make the mapping checkable without re-reading both sides |
| `podcasts-gtk/src/chapter_parser/{id3,extended_comment}.rs` | 2 | 3 `it` blocks in `spec/chapter_parser_spec.rb` cover this ground most faithfully of anything in the port — closest the suite gets to a real mapping, still not named 1:1 |
| `podcasts-gtk/src/manager.rs` | 2 | 0 named directly; `test/drive_covers.rb` exercises `download_manager.rb` behaviourally |
| `podcasts-data/src/{database,pipeline,parser}.rs` | 3 | 1–2 `it` blocks touch adjacent ground, not named |

**Total named/mapped-by-construction: 0 of 123.** Not because the port tests
nothing — it runs 20 rspec examples and 97 driven UI checks, all green — but
because none of those 117 total test units was written *as* the upstream
test it corresponds to, with the upstream test's name or identifier
preserved per the skill's naming convention (`test_add_minimal` ↔
`/cli/argument_parser/add_minimal`). The port's suite is real, substantial,
and passing — and it is **extra**, in the skill's terms, not **ported**.

## This report is itself incomplete, stated plainly

A full row-by-row ledger (123 rows, one upstream test per row, Purpose +
Port test + State) is the deliverable the skill asks for and this audit did
not build it — the per-case reading of all 123 upstream tests (especially
the 10 `new_show`/`new_episode` validation cases and the 23 Nextcloud cases)
was not done to that depth in this pass. That is a **gap in this audit**,
named as such rather than rounded up to "roughly ported" or left implied.
The honest number this report can stand behind is:

- **123 upstream tests exist** (census run, reproducible).
- **At most 20 of them have any plausible port counterpart at all**, by
  subject-matter overlap, and even those 20 are not written as 1:1 named
  pairs — several demonstrably merge multiple upstream cases.
- **13 (episode_description_parser) are claimed ported in a report with zero
  test evidence.** That is a false green, independent of how the eventual
  row-by-row census resolves.
- **23 (nextcloud_sync) cannot be ported at all** until that component exists.
- The suite that **does** exist is green and was verified running in this
  audit, which is worth stating precisely so it is not conflated with test
  parity: `20/20 rspec`, `97/97 drive checks`, both reproduced live.

## Extra

- `spec/data_layer_spec.rb` (17 `it`s), `spec/chapter_parser_spec.rb` (3
  `it`s) — real coverage of the data layer and chapter parser, not mapped to
  specific upstream tests.
- `test/drive_covers.rb`, `test/drive_discovery.rb`,
  `test/drive_episode_description.rb`, `test/drive_main_window.rb` — 97
  driven UI checks. Upstream has no equivalent GTK-driving test suite in
  Rust for these pages, so this is wholly extra, and valuable: it is the only
  thing in the repo that opens a real window and clicks on it.

## Open

- Resolve the `podcasts-gtk/src/utils.rs` 3-vs-7 discrepancy between hand
  count and `test-census.sh` before quoting 123 as final.
- Build the full 123-row ledger per the skill's `TEST_PARITY.md` format.
  Until that exists, no one can mechanically re-verify "which upstream test
  does `data_layer_spec.rb:123` correspond to," and that is exactly the
  ambiguity the bijection rule exists to remove.
