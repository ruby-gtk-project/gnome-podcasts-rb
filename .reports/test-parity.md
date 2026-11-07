# Test parity — gnome-podcasts-rb

| | |
|---|---|
| Upstream | `main` @ `35d671f6` (worktree pinned for this audit; record this sha) |
| Port | `ruby` @ `598982e3` (re-run this pass; the prior pass at `4b0942a4` is superseded below) |
| Upstream tests (census) | **123** (`scripts/test-census.sh`, cross-checked by hand against `#[test]` occurrences per file: 121 by hand-count, 123 by script — the 2-test discrepancy is `podcasts-gtk/src/utils.rs`, 7 by script vs 3 counted by eye; not resolved in this pass, see "Open" below) |
| Ported (named, bijective) | **13** confirmed by name (`spec/episode_description_parser_spec.rb`, added in `4baf0f22` after the prior pass of this report; see below). The other 110 remain **0** by name. |
| Gaps | up to 110, pending the row-by-row census this report does not complete |
| Suite actually run | **yes** — both commands below were executed in this audit, not assumed |
| Test command | `nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'` → `33 examples, 0 failures` |
| Drive command | `nix develop --command xvfb-run -a ruby test/drive_*.rb` → `19+38+3+37 = 97 of 97 checks passed`, `DRIVE OK` on all four |

## What was actually run in this audit, and the result

Both commands above were executed live, not inferred from a prior claim:

```
33 examples, 0 failures
```

(Rerun of this report's own prior pass, which recorded `20 examples, 0
failures` at `4b0942a4`. The +13 is `spec/episode_description_parser_spec.rb`,
added in `4baf0f22`, between that pass and this one — see "Update" below.)

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
| `podcasts-gtk/src/episode_description_parser.rs` | 13 | **13, named 1:1** — `spec/episode_description_parser_spec.rb` (added `4baf0f22`, after this report's prior pass) carries one `it` per upstream `#[test] fn`, each with upstream's own description/fixture string verbatim. Verified running live in this pass: `13 examples, 0 failures` in isolation, and included in the `33 examples` total above. This closes what was previously a false-green claim in `.reports/component-inventory.md:226` — see `.reports/accountability-ensurance.md` Finding 1, now marked closed. This is the **only** upstream file in this table with a true 1:1 named mapping. |
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

**Total named/mapped-by-construction: 13 of 123** (episode_description_parser,
confirmed above). The port runs 33 rspec examples and 97 driven UI checks,
all green — but apart from those 13, none of the remaining ~104 test units
was written *as* the upstream test it corresponds to, with the upstream
test's name or identifier preserved per the skill's naming convention
(`test_add_minimal` ↔ `/cli/argument_parser/add_minimal`). The rest of the
port's suite is real, substantial, and passing — and it is **extra**, in the
skill's terms, not **ported**.

## This report is itself incomplete, stated plainly

A full row-by-row ledger (123 rows, one upstream test per row, Purpose +
Port test + State) is the deliverable the skill asks for and this audit did
not build it — the per-case reading of all 123 upstream tests (especially
the 10 `new_show`/`new_episode` validation cases and the 23 Nextcloud cases)
was not done to that depth in this pass. That is a **gap in this audit**,
named as such rather than rounded up to "roughly ported" or left implied.
The honest number this report can stand behind is:

- **123 upstream tests exist** (census run, reproducible).
- **13 (episode_description_parser) are confirmed ported 1:1 by name**,
  verified running (`13 examples, 0 failures` in isolation) in this pass.
  This was a false-green claim as of the prior pass of this report; it no
  longer is.
- **At most ~20 more of the remaining 110 have any plausible port
  counterpart at all**, by subject-matter overlap, and none of those is
  written as a 1:1 named pair — several demonstrably merge multiple
  upstream cases.
- **23 (nextcloud_sync) cannot be ported at all** until that component exists.
- The suite that **does** exist is green and was verified running in this
  audit, which is worth stating precisely so it is not conflated with test
  parity: `33/33 rspec`, `97/97 drive checks`, both reproduced live.

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
