# irx — inverted-pair regex fuzzer for d8

Implementation of [`spec.md`](spec.md). irx picks an accept string A and a
reject string R, builds a finite tree grammar whose nonterminals are
(rel_A, rel_R) span-relation pairs, samples regexes that *provably* fully match
A and fully reject R, and reports any case where V8 (`d8`) disagrees. Every
case has its own model-derived oracle; independent engines are optional sanity
checks.

## Build and test

Requires the exact Zig version in `.zigversion` (0.16.0). macOS on Apple
Silicon is the primary target. Only POSIX/Darwin APIs are used.

```sh
zig build test                        # unit tests (Debug, safety checks on)
zig build -Doptimize=ReleaseFast      # benchmark/campaign build -> zig-out/bin/irx
```

## Usage

```sh
irx --d8 ./d8 --config weights.toml --jobs 0 --seed 42 --out findings/ \
    [--modes interp,native,tierup] [--optional-modes linear,noopt,nopeephole,fallback0] \
    [--jsc PATH] [--sm PATH] [--max-cases N] [--duration SECONDS] [--no-selfcheck]
irx selfcheck --d8 ./d8 [--config F] [--out DIR] [--sm PATH]   # atom/assertion self-check only
irx replay findings/findings/000001 --d8 ./d8                  # model recheck, table digest, re-derive, rerun
irx triage --d8 ./d8 --out findings/                           # resume triage of untriaged findings
irx gate --d8 ./d8 --out gate/                                 # performance gate over src/gate_corpus.toml
irx sample [--config F] [--seed N] [--max-cases N]             # distribution diagnostics (no engine)
```

`--jobs 0` uses `sysctl hw.physicalcpu` as the ceiling on sampling d8
processes; with M active modes there are floor(jobs / M) lanes. The allocation,
the unused slots, and the single extra triage child are printed at startup.

The once-per-second stats line on stderr shows cases/s, per-stage times
(sample, print, encode, engine wait), pairs/prods of the latest table, managed
bytes and RSS (host and children), findings, pending triage queue, zero-mass
retries, per-mode executed/skipped/mismatch/restart counts, tier
first-seen/repeated counts (transitions unverified), and slow cases.

## Output layout

```
OUT/manifest.json       seeds, build identity, d8 path/hash/version, driver hash, Unicode manifest,
                        resolved config, per-flag-set atom and quantifier inventories, mode flags, probes
OUT/config.toml         copy of the config used (replay/triage read it automatically)
OUT/tables.log          every table: identity, A/R/flags, digest, per-level build stats and truncation
OUT/selfcheck/report.txt
OUT/findings/NNNNNN/    case.irx (machine-readable), case.json, repro.js, manifest.json,
                        triage.json, repro.min.js + minimized.irx (semantic findings),
                        batch.req/stderr.txt/isolated.req/sequence.jsonl (crash/timeout findings),
                        occurrences (byte-identical recurrences)
OUT/groups/KIND__MODE__CONSTRUCTS.txt   navigation index; members are never deleted
OUT/slow/index.txt      timeouts, kept apart from semantic findings
OUT/journals/           per-process request journals (deleted only if unreferenced after retirement)
OUT/summary.json        end-of-run totals
```

## Module map

| File | Role |
| --- | --- |
| `src/rel.zig` | `Rel(N)` for N ∈ {8, 16}: product, closure (Warshall), bounded powers by squaring, lookaround diagonals |
| `src/ucd.zig`, `src/ucd/` | Vendored Unicode 17.0.0 (CaseFolding, UnicodeData, SpecialCasing) with SHA-256 manifest verified at startup |
| `src/alphabet.zig` | Flags, UTF-16 → symbol decoding per mode, line terminators, `\s`, word chars, Canonicalize for i / iu / iv |
| `src/atoms.zig` | Atom specs and ES2024 CharacterSetMatcher semantics (incl. v-mode set ops, MaybeSimpleCaseFolding, folded-universe complements), assertion masks, inventory |
| `src/ast.zig` | Owned trees, direct relation evaluation, naive backtracking matcher (cross-check), s-expression serialization |
| `src/table.zig` | Grammar inventory, Robin Hood interner, production set, budgeted semi-naive levels, Vitter Method D combo sampling, usefulness pruning, renumbering, log-space counts, digest |
| `src/budget.zig` | Hard byte accounting (`max_table_bytes` per table under `max_host_bytes`) on every allocation |
| `src/sample.zig` | Lazy per-(pair, size) Walker/Vose alias tables (CAS-published arena), split inversion, mode-aware printer |
| `src/harness.zig` | `posix_spawn` with QoS and null crash exception ports, nonblocking poll transport, deadlines, journals, novelty set, mode probes |
| `src/lane.zig` | Per-lane sample → fan-out → compare → persist loop |
| `src/run.zig` | Table publication (mutex-exchanged strong refs), background builder, bounded retries, adaptive weights, triage queue with disk overflow |
| `src/shrink.zig` | Triage: fresh-process reproduction, tree/string/flag shrinking, batch isolation/bisection, journal prefix replay, sanity classification |
| `src/selfcheck.zig` | Startup atom and assertion self-check against d8 and optional independent engines |
| `src/finding.zig` | Owned cases, failure predicates, finding persistence, lossless dedup |
| `src/main.zig` | CLI, config, probing, manifests, stats line, gate/replay/triage/sample commands |
| `driver.js` | Batch driver with d8/SpiderMonkey/JSC adapters (embedded; its hash is in the manifest) |

## Validation status

* **Model vs. backtracking matcher**: >3,000 random trees across 11 flag sets agree (`ast.zig` test).
* **Flag-semantics checklist**: unit tests for `[^k]` under i/iu/iv, `\W` vs ſ/K (Kelvin sign), `[a--A]`/`[a&&A]` under iv,
  dot/line terminators, `^ $ \b \B` under m and iu, case-insensitive literals, lone surrogates.
* **Atom self-check against d8 15.5**: 744,480 probes over all 24 flag sets (every consuming atom × pool symbols,
  out-of-pool case variants, lone surrogates, multi-symbol/multiline subjects; every assertion at every position)
  — **0 mismatches**. Injecting a one-line model bug (Kelvin sign treated as non-word under iu) yields 1,004
  mismatches, so the check has teeth.
* **Counts**: exhaustive enumeration of small grammars matches table counts to <1e-5 relative error, including
  extreme weight ratios (1e-3 … 50). Sampling frequencies match exact tree probabilities within 5.5σ over 60k
  draws, on both the cached and uncached alias paths.
* **Transport**: tests for partial writes (600 KB and 2 MB requests), malformed responses, a child that stops
  reading during batch 1 while batch 2 is being sent (recovers by deadline, no watchdog thread), stderr flooding
  (bounded tail, truncation counted), signal death, EOF/malformed handshake.
* **Budgets**: deterministic truncation under tiny caps (identical digests), resource rejection with zero leaked
  bytes, zero-mass rejection, A = R rejection, finite retry exhaustion (gate scenario `retry-exhaustion`).

## First results: a V8 15.5 irregexp regression

Within 45 seconds the fuzzer reported (and triage reproduced and minimized) wrong results in every d8 mode
of V8 15.5.35.20 (Homebrew):

```js
/(?:.*?B^|a)/s.test("a")        // d8 15.5: false   expected/ES spec & Node 25 (older V8): true
/^(?:.*?a^)*$/s.test("")        // d8 15.5: false   expected: true (zero iterations)
/a(?:.*?[A-Z]^)|aa/s.test("aa") // d8 15.5: false   expected: true
```

Lazy any-char loops followed by a class and `^` make later alternatives (or the empty iteration) unreachable.
`--no-regexp-quick-check` restores the correct answer in all three cases; `--no-regexp-optimization` fixes the
first but not the second. The experimental linear engine (`l` flag) answers correctly. The jsvu SpiderMonkey
shell returns the same wrong answers — it vendors V8's irregexp, so its agreement is *not* independent evidence
(triage says so in `classification`). This has not been reported upstream; per the spec it is a reproduced
candidate, not a confirmed V8 bug, until reviewed.

## Deviations, limitations and measured decisions

* **Default weights** were rebalanced after measurement: with all-ones weights, ~50% of nodes were quantifiers
  nested 3–5 deep, and nearly every 512-case batch timed out on catastrophic backtracking. Defaults now favour
  concat/alt (see `weights.toml`); typical nesting depth is 1–2.
* **Shared lazy alias cache is enabled by default.** Measured: uncached sampling cost ~3 ms/case on large
  tables (ReleaseFast); with the cache, ~7 µs/case amortized over 100k samples per table. Cached and uncached
  paths use identical ordering, arithmetic and RNG draws.
* **Class templates** are enumerated as positive or negated listings of up to `class_max_members` pool symbols
  (equivalent to pool-member bits plus the "other" bit under a member-count limit).
* **Tree shrinking** uses structural AST reductions with direct relation evaluation (the spec's documented
  fallback); grammar reconstruction is used for replay digest verification, not witness search. The limitation
  is recorded in each `triage.json`.
* **Tier transitions are reported as unverified**: `--trace-regexp-tier-up` is read-only in the Homebrew build
  (probed by launching, not by `--help`). Repeated-execution semantics are still tested in `tierup` mode.
* **JSC** is not installed on this machine; the adapter exists (`--jsc PATH`). SpiderMonkey via jsvu works
  (`--sm ~/.jsvu/bin/sm`) but shares irregexp.
* **linear mode** skips `m` cases (`multiline-wrapper`) and marks u/v and lookaround cases as
  `engine-unsupported`; both are counted and never treated as agreement.
* **One batch in flight per lane**; the two-in-flight option and parallel table construction are not
  implemented (the spec gates them on measurements).
* **Peak-phase memory** is enforced by hard per-allocation checks through budgeted allocators plus a startup
  feasibility check (lanes' scratch + two tables + triage); there is no separate precomputed worst-phase
  reservation.
* **Finding artifacts** are written atomically (temp + rename) without fsync; fsync per file dominated
  persistence cost when a bug produced thousands of distinct findings.
* **Counting cost**: at the spec's default caps a table hits `max_count_terms` around level 5–6 and takes
  ~3 s to build in ReleaseFast. Tune `max_count_terms`/`samples_per_table` per campaign.
* **ASan pool**, **d8 source build** and **Linux** are not exercised here; d8 was the Homebrew release build
  (not `dcheck_always_on`). The spec's recommended GN args remain the right choice for real campaigns.
