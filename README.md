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

## Layout: dialects, targets, hosts

* `src/dialect.zig` — the **Dialect** component interface; `src/dialects/*.zig` implement it, one model per engine family (es, perl, swift, rust/fancy, re2/go, python, java, ruby/oniguruma, dotnet, icu, resharp, nim, racket, tcl, emacs, vectorscan, llvm)
* Span mode (`[span] enabled = true` in a target's `target.toml`, with `units` = `utf16`, `cp` or `utf8`): a third mode (`shell-span`, `perl-span`, or `span` for d8) where the host runs an unanchored search on A and R and reports the first match's `[start, end)` (4 bytes per case, `src/span.zig`). irx converts the host's units to UTF-16 offsets and compares them with the reference: the backtracking matcher's first match in priority order (`span_semantics = .first`), or the leftmost-longest span from the relation (`.longest`: LLVM, Tcl, RE#). Loops whose body matched empty end the loop (Perl/PCRE family, `empty_iteration = .stop`) or reject that path (ES, `.reject`); engines with their own rule (RE2, Go, Rust, .NET NonBacktracking: `.unmodeled`) skip patterns with such loops. Mismatches are `wrong_span` findings with the expected/observed spans in the manifest and triage report. Vectorscan has no span mode.
* Capture mode (`[capture] enabled = true`, `loop` = `reset`/`keep`/`unmodeled`, optional `lookbehind = false`): like span mode, but the host also reports groups 1–6 (`src/capture.zig`), checked against the matcher's capture slots. The printer maps tree groups to printed group numbers (the `()` empty spelling adds groups) and names named groups `gN` after their printed number. Mismatches are `wrong_capture` findings. Design and engine survey: [docs/phase2-captures.md](docs/phase2-captures.md).
* Empty-atom spellings: each fuzz case carries a `spell` seed (recorded in `case.irx`, reused by the shrinker and replay) that prints every empty atom as `(?:)`, as nothing where the syntax allows (`(?:|a)`, `a|`, `(?=)`), or as `()`. Parser bugs often depend on the spelling. Dialects can opt out (`bare_empty`, `empty_capture`); the self-check always uses `(?:)`.
  (character predicates, case rules, anchors, escape syntax, string/flag/grammar constraints). Selected with
  `--dialect`. Semantic only, so a future match-range oracle can reuse it.
* `targets/<name>/target.toml` — one per engine: how to launch it (`kind`, `command`), which dialect models it,
  whether to self-check, and a config overlay (e.g. no lookbehind). `targets/<name>/README.md` holds that
  engine's campaign results.
* `hosts/` — protocol hosts shared by several targets (C, Go, Rust, Java, .NET, Swift, Nim, Racket, Emacs,
  scripting languages); `hosts/build.sh` builds the native ones into `hosts/bin/`.
* `tools/irx_target.py NAME | --all [--duration S]` — runs campaigns from target definitions and refreshes the
  target's README block. Older per-engine branches were folded into `targets/` and archived as tags
  `archive/<name>`.

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
| `src/dialect.zig`, `src/dialects/` | Dialect component interface and one exact model per target engine (`tools/probe.py` asks a host ad-hoc questions while writing one; `tools/gen_emacs_tables.py` regenerates the Emacs tables) |
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

## Candidate V8 bugs found

About 15 million patterns (roughly 50–60 million regex executions across 3–6 d8 modes) against
V8 15.5.35.20 (Homebrew d8) produced three wrong-result candidates. All reproduce in fresh processes and
were minimized by the fuzzer's own triage. None has been checked against current V8 main or Chrome, and
IRX-V8-2 and IRX-V8-3 have user-provided Chromium issue links in the bug ledger below; the issue contents could not be checked here. The others remain unreported candidates.

| # | Minimized repro | d8 15.5 | Correct (ES spec) | Notes |
|---|---|---|---|---|
| 1 | `/(?:.*?B^\|a)/s.test("a")` | `false` | `true` | Fixed by `--no-regexp-quick-check` and by `--no-regexp-optimization`. Node 25.8 (older V8) and the `l` linear engine are correct. |
| 2 | `/^(?:.*?a^)*$/s.test("")` | `false` | `true` (zero iterations) | Fixed by `--no-regexp-quick-check` but **not** by `--no-regexp-optimization`, so possibly distinct from #1. Node 25.8 is correct. |
| 3 | `/(?<![\s\S])(?:(?:^)*)(?![\s\S])/mu.test("😀")` | `true` | `false` | A unicode-mode match apparently starts between the two halves of a surrogate pair. Not affected by `--no-regexp-quick-check`. The simpler `/(?<![\s\S])(?![\s\S])/u` is correct in 15.5 but wrong in Node 25.8 (match at index 1), so this looks like a surviving variant of an older bug. |

Candidates 1 and 2 have the same shape: a lazy any-char loop followed by an unsatisfiable `^`, after which
V8 skips later alternatives (or the empty iteration). They account for every quick-check finding seen
(~25 tables, all with the `s` flag). Candidate 3 produced ~8.8k distinct findings from a single `msu` table whose
reject string contained surrogate pairs. The jsvu SpiderMonkey shell gives the same wrong answers for all
three; it vendors V8's irregexp, so its agreement is not independent evidence.

First detection took about 6 seconds of fuzzing (candidates 1 and 2); candidate 3 appeared in the
edit-distance-5 campaign (`[strings] max_edit_distance = 5`).

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

<!-- BEGIN shared bug ledger (identical on every branch) -->
## Bug ledger

Two sources: bugs found by this inverted-pair fuzzer (irx), and bugs found earlier by differential fuzzing in
the sibling repo [`../regex_comparison`](../regex_comparison/bugs/BUGS.md) (imported 2026-10-09; IDs link to
that repo's write-ups, which hold full repros and upstream-search notes). None of the irx findings has been
reported upstream except IRX-V8-2, IRX-V8-3, IRX-DOTNET-6–8, and IRX-SWIFT-1–3 (issue links below). Older V8 builds (Node 25.8 = V8 14.1, Deno 2.9.7 = V8 15.0) are fuzzed on the
`node`/`deno` branches but excluded from this ledger: d8 15.5 is the up-to-date V8 target.

### Found by irx

| ID | Engine | Status | Repro (observed → expected) | Report | Notes |
|---|---|---|---|---|---|
| IRX-V8-1 | V8 | unreported | wrong result: `/(?:.*?B^\|a)/s.test("a")` → `false` → expected `true` | not filed | Tested: V8 15.5.35.20 (d8). quick-check family; fixed by `--no-regexp-quick-check` and `--no-regexp-optimization`. Same family as [V8-3](../regex_comparison/bugs/BUGS.md#v8-3) |
| IRX-V8-2 | V8 | reported | wrong result: `/^(?:.*?a^)*$/s.test("")` → `false` → expected `true` | [Chromium #572154295](https://issues.chromium.org/issues/572154295) | Tested: V8 15.5.35.20 (d8). user-provided link (mapping inferred from filing order); fixed by `--no-regexp-quick-check`, not by `--no-regexp-optimization` |
| IRX-V8-3 | V8 | reported | wrong result: `/(?<![\s\S])(?:(?:^)*)(?![\s\S])/mu.test("😀")` → `true` → expected `false` | [Chromium #572331418](https://issues.chromium.org/issues/572331418) | Tested: V8 15.5.35.20 (d8). user-provided link (mapping inferred from filing order); match starts inside a surrogate pair; related to [V8-1](../regex_comparison/bugs/BUGS.md#v8-1) / [V8-2](../regex_comparison/bugs/BUGS.md#v8-2) |
| IRX-V8-4 | V8 | unreported | wrong span (inside a surrogate pair): `/(?!.)\|a^/u.exec("😀").index` → `1`; also `/\n\|(?!^)/u` → expected `2` (`/(?!.)/u` alone gives `2`) | not filed | Tested: V8 15.5.35.20 (d8). the V8-2 surrogate-pair problem is still reachable in current V8 when the zero-width branch sits in an alternation; Node 25 (V8 14.1) also fails the single-branch form. Found by span mode |
| IRX-PERL-1 | Perl | unreported | wrong result: `"0a" =~ /\A(?=a*)[0-9]a\z/` → false → expected true | not filed | Tested: Perl 5.34.1, 5.44.0, blead 5.45.4. Rechecked on freshly built upstream blead `23257acb8515` (2026-10-10): still reproduces. Optimizer builds an empty start class (`re 'debug'`: `synthetic stclass "ANYOF[]"`); also in loops: `"b" =~ /\A(?:(?=a*).)+\z/` |
| IRX-PERL-2 | Perl | unreported | wrong result: `"a" =~ /\A^\ba*\z/m` → false → expected true | not filed | Tested: Perl 5.34.1, 5.44.0, blead 5.45.4. Rechecked on freshly built upstream blead `23257acb8515` (2026-10-10): still reproduces. Also reduces to `"a" =~ /^\ba*$/m` → false (expected true); needs `/m`, `^`, `\b` and an optional quantifier (`*` or `?`), but not `\A` |
| IRX-PERL-3 | Perl | unreported | wrong capture: `"aa" =~ /(?:(aa){2})*/` → match `[0,0)` but `$1` = `"aa"` at `[0,2)`; `"aaaaaa" =~ /(?:(aa){2,2})+/` → match `[0,4)`, `$1` at `[4,6)` (outside the match) → expected `$1` undef; `$1` at `[2,4)` | not filed | Tested: Perl 5.44.0 (5.34.1 is correct). a capture set during a loop iteration that later fails is not restored; likely from the 5.38 change that resets captures in quantified groups (perl5380delta). Found by capture mode (phase 2) |
| IRX-XS-1 | XS | unreported | rejects valid pattern: `new RegExp("[]", "v")`, `new RegExp("[^]", "v")` → SyntaxError → expected accepted (ES2024) | not filed | Tested: XS (jsvu, Moddable). empty `ClassContents` is legal in UnicodeSets mode |
| IRX-BOA-1 | Boa | unreported | rejects valid input (JSON): `JSON.parse('"\\ud83d"')` → SyntaxError → expected 1-unit string | not filed | Tested: Boa (`boa_cli`, cargo). lone-surrogate escapes are valid JSON; not a regex bug, found while wiring the harness |
| IRX-BOA-2 | Boa | unreported | wrong result: `/^[\uD83D\uDE00]$/.test("\ud83d")` → `false` → expected `true` | not filed | Tested: Boa (`boa_cli`, cargo). without `u`, an escaped high surrogate followed by another escape in a class is mishandled (also `[\uD83D\u03A3]`) |
| IRX-BOA-3 | Boa | unreported | wrong result: `/^s$/i.test("ſ")` → `true` → expected `false` | not filed | Tested: Boa (`boa_cli`, cargo). non-`u` `i` uses Unicode simple folding instead of `toUpperCase` canonicalization; `\w`/`i` also matches ſ and K |
| IRX-BOA-4 | Boa | unreported | wrong result: `/^(?:\D\b)$/iv.test("\u212a")` → `false` → expected `true` | not filed | Tested: Boa (`boa_cli`, cargo). `\b` ignores the extra `iu`/`iv` word characters (ſ, K) |
| IRX-BOA-5 | Boa | unreported | wrong result: `/^(?:(?:\s(?:(?:){0,1}\|a))+)+$/.test("\u2028a")` → `false` → expected `true` | not filed | Tested: Boa (`boa_cli`, cargo). an empty group quantified `{0,1}` as an alternative breaks nested loops; `(?:\|a)` is fine |
| IRX-BOA-6 | Boa | unreported | wrong result: `/^[s[^a]]$/iv.test("a")` → `true` → expected `false` | not filed | Tested: Boa (`boa_cli`, cargo). nested complements in `v` classes are not case-folded under `i` |
| IRX-BOA-7 | Boa | unreported | wrong result: `/(?:(?:a+)+){2}/.test("aa")` → `false` → expected `true` | not filed | Tested: Boa (`boa_cli`, cargo). a counted repeat of a group whose body is a quantified quantifier; `(?:(?:a+){1}){2}` and `(?:(?:a{2,3}){2}){2}` on `"a"×8` fail too, `(?:a+){2}` and `(?:(?:a+)*){2}` are fine; also Hermes (IRX-HERMES-3) and XS (IRX-XS-4) |
| IRX-BOA-8 | Boa | unreported | hang: `/(?:(?:a\|)*)*b/.test("a")` never returns → expected `false` | not filed | Tested: Boa (`boa_cli`, cargo). a nullable alternative inside two nested stars loops forever once the match fails; also `(?:(?:a\|(?:)?)*)*b`. Accounts for most Boa batch timeouts |
| IRX-QJS-1 | QuickJS | unreported | rejects valid pattern: `new RegExp("-", "v")`, `new RegExp("a-b", "v")` → SyntaxError → expected accepted | not filed | Tested: QuickJS (Homebrew `qjs`). `-` outside a class is an ordinary character in UnicodeSets mode (d8, XS accept) |
| IRX-PCRE2-1 | PCRE2 | unreported | wrong result: `/(?<!(?:\|a)$)a/` on `"a"` → no match; `/(?<=a?\b)a/`, `/(?<!a?\B)a/` on `"a"` → no match → expected match | not filed | Tested: PCRE2 10.49 **JIT** (also PHP 8.5 `preg_*`, JIT on by default). interpreter correct; a lookbehind (positive or negative) whose body is a variable-length part (`a?`, `a??`, `(?:\|a)`) next to `$`, `\z`, `\b` or `\B`. `(?<=a?^)a`, `(?<=a?)a` and `(?<!(?:\|a)x)a` are fine |
| IRX-PCRE2-2 | PCRE2 | unreported | wrong span: `pcre2_match("(?:^\\B\|..){0,2}\\S", " .-x0")` → `[0,3)` → expected `[0,5)` (Perl, V8) | not filed | Tested: PCRE2 10.49 (interpreter and JIT; also PHP 8.5). after the first iteration matched empty (`^\B` at 0) and was backtracked into `..`, the second iteration is never tried before `\S`; with a literal (`…{0,2}0`) the span is right. Found by span mode; also `(?:^\|.){0,3}\\B` on `"aa-"` → `[0,1)` (Perl `[0,3)`) |
| IRX-PCRE2-3 | PCRE2 | unreported | wrong result (no match): `/(?:é\| )\\D{2}/u` on `" aa"` → no match under `pcre2_jit_compile`; also `\\S{2,}`, `\\w{2,}`, first branch `ı` or `σ` → expected `[0,3)` (interpreter) | not filed | Tested: PCRE2 10.49 **JIT** (also PHP 8.5). an alternation whose first branch is a non-ASCII literal and whose later branch matches, followed by a class escape repeated two or more times; `(?: \|é)`, `[é ]`, `\\D{1,}` and `[^0-9]{2,}` are fine. Found by span mode on PHP |
| IRX-SWIFT-1 | Swift Regex | reported | wrong result: `/\w\b\w/` matches `"a0"`; `/0\b/` misses `"0"` → expected no; yes | [swift-experimental-string-processing #901](https://github.com/swiftlang/swift-experimental-string-processing/issues/901) | Tested: Swift Regex (Swift 6.4), `.unicodeScalar` semantics + `.simple` word boundaries. `\b` treats digits as non-word although `\w` matches them; grapheme semantics is correct |
| IRX-SWIFT-2 | Swift Regex | reported | wrong result: `try Regex("k+").ignoresCase()` does not match `"K"` (U+212A, Kelvin), nor `"KK"` → expected match (`k` alone and `kk*` on one `K` do match) | [swift-experimental-string-processing #900](https://github.com/swiftlang/swift-experimental-string-processing/issues/900) | Tested: Swift Regex (Swift 6.4), `.unicodeScalar` semantics, `ignoresCase()`. a quantified case-insensitive literal skips the Unicode case variant that the single literal honours |
| IRX-SWIFT-3 | Swift Regex | reported | wrong result: `\A(?:^\|a){2,}\z` and `\A(?:a\|^){2,}\z` miss `"a"` → expected match | [swift-experimental-string-processing #899](https://github.com/swiftlang/swift-experimental-string-processing/issues/899) | Tested: Swift Regex (Swift 6.4), `.unicodeScalar` semantics. an open-ended counted group that needs a zero-width iteration; `{2}` and `{2,3}` are fine. Same family as IRX-JAVA-2 and IRX-ONIG-1 |
| IRX-TCL-1 | Tcl | unreported | wrong result: `regexp -nocase {^k{1}$} "\u212a"` → `0`; also `k+`, `k*`, `[k]+` → expected `1` (`regexp -nocase {^k$} "\u212a"` → `1`) | not filed | Tested: Tcl 9.1.0 (`regexp -nocase`). a quantified case-insensitive `k` loses the Kelvin-sign variant that the bare literal matches. Same as IRX-SWIFT-2; found by cross-checking |
| IRX-DOTNET-1 | .NET | resolved | crash (exception): `Regex.IsMatch("aa", @"\A(?:(?=(?:)+?a)a)\z")` → `IndexOutOfRangeException` → expected `false` | not filed | Tested: .NET 9.0.4 Regex interpreter. **resolved in current version (.NET 11 RC 1)**; the recorded .NET 9.0.4 exception does not occur |
| IRX-DOTNET-2 | .NET | resolved | crash at construction: `new Regex(@"\A(?:a(?<=(?:)??))\z", RegexOptions.Compiled)` → `ArgumentException: Bad label content in ILGenerator` → expected compiles, matches `"a"` | not filed | Tested: .NET 9.0.4 `RegexOptions.Compiled`. **resolved in current version (.NET 11 RC 1)**; construction and matching succeed; interpreter was already fine |
| IRX-DOTNET-3 | .NET | resolved | wrong result: `Regex.Match("aa", @"(?:a(?:)+?)+")` → `[1,2)`; `\A(?:(?:a\|(?=a))+?){2}\z` misses `"a"`; `\A(?:(?:aa(?:)*?){2})*\z` matches `"a"×6` → expected `[0,2)`; match; no match | not filed | Tested: .NET 9.0.4 Regex interpreter. a lazy loop over a nullable body inside another loop: the outer loop iterates wrongly in both directions; Compiled and NonBacktracking are correct. **resolved in current version (.NET 11 RC 1)**; all recorded cases now give the expected result. In .NET 9.0.4 span mode also returned **impossible matches**: `Regex.Match("", @"(?:(?:)+?){2}")` → Index 0, Length 3; `Regex.Match("a", @"(?:a()+?)*")` → Index 1, Length 2 (past the end) |
| IRX-DOTNET-4 | .NET | resolved | crash (exception): `new Regex(@"\A(?:(?:a\|(?:\B){2,}?)a)*a\z", RegexOptions.Compiled).Match("aaa")` → `ArgumentOutOfRangeException: Non-negative number required. (Parameter 'newSize')` → expected match | not filed | Tested: .NET 9.0.4 `RegexOptions.Compiled`. **resolved in current version (.NET 11 RC 1)**; lazy counted `\B` in an alternative inside a loop; interpreter was already correct |
| IRX-DOTNET-5 | .NET | resolved | wrong result: `\A(?:(?:){2,3}?a)*\z` misses `"a"`; `\A(?<!(?:aa)+?)a\z` misses `"a"`; `\A(?:(?:a\|$\|(?:\B){2,}?a\|a)a)*a\z` misses `"aaaaa"` → expected match | not filed | Tested: .NET 9.0.4 `RegexOptions.Compiled`. lazy loops with a lower bound (`{2,3}?`, `+?`, `{2,}?`) inside a loop or lookbehind; `{2}?` is fine. Interpreter and NonBacktracking correct. Same area as IRX-DOTNET-4; **resolved in current version (.NET 11 RC 1)** across all three recorded cases |
| IRX-DOTNET-6 | .NET | reported | wrong result: `new Regex(@"^a (?:\Ba\|\ba)+$", RegexOptions.NonBacktracking).IsMatch("a aa")` → `false`; without `$` the match is `[0,3)` → expected `true`; `[0,4)` | [dotnet/runtime#135586](https://github.com/dotnet/runtime/issues/135586) | Tested: .NET 9.0.4 `RegexOptions.NonBacktracking`. still reproduces in .NET 11 RC 1; a loop whose alternatives start with `\b` and `\B` stops after one iteration when the pattern begins with `^`; without `^` it is correct, and the backtracking engines are correct |
| IRX-DOTNET-7 | .NET | reported | wrong span (differs from backtracking): `new Regex("(?:aa\|aaa)+a", RegexOptions.NonBacktracking).Match("aaaaaaaa")` → `[0,8)`; also `(?:a\|.{3,}){0,2}.` on `"abaa"` → `[0,4)` → expected `[0,7)`; `[0,2)` (the interpreter's match) | [dotnet/runtime#135585](https://github.com/dotnet/runtime/issues/135585) | Tested: .NET 9.0.4 `RegexOptions.NonBacktracking`. still reproduces in .NET 11 RC 1; NonBacktracking takes a later, longer match when a loop has to give back an iteration. Lazy loops (`a+?`) agree. Found by span mode |
| IRX-DOTNET-8 | .NET | reported | wrong span: `Regex.Match("aaaaK", @"(?:(?:a.?)+){2}")` → `[0,4)`; also `(?:(?:ab?)+){2}` on `"aaab"` → `[0,4)` → expected `[0,5)` (Perl, PCRE, Python, Java, V8) | [dotnet/runtime#135584](https://github.com/dotnet/runtime/issues/135584) | Tested: .NET 9.0.4, all three engines (interpreter, `Compiled`, `NonBacktracking`). filed with DOTNET-6; still reproduces in .NET 11 RC 1; an exact count over a greedy loop doesn't retry the first iteration with a shorter inner match that lets the second one take more; the unrolled `(?:(?:a.?)+)(?:(?:a.?)+)` gives `[0,5)`. Full matches are right (`\A…\z` gives `[0,5)`). Found by span mode |
| IRX-XS-2 | XS | unreported | wrong result: `/^[S\u{1F600}]$/iv.test("s")` → `false`; `/^[^A]$/iv.test("a")` → `true` → expected `true`; `false` | not filed | Tested: XS (jsvu, Moddable). `v`-mode classes ignore `i`: neither members nor complements are case-folded (~250 findings) |
| IRX-XS-3 | XS | unreported | uncatchable abort (sequence-dependent): a 512-case batch aborts the script with uncaught `RangeError: buffer overflow` although every case runs inside `try` → expected per-case result bits | not filed | Tested: XS (jsvu, Moddable). 780 batches; no single case aborts alone, not yet minimized |
| IRX-XS-4 | XS | unreported | wrong result: `/^(?:(?:a+){1}){2}$/.test("aa")` → `false` → expected `true` | not filed | Tested: XS (jsvu, Moddable). the IRX-BOA-7 / IRX-HERMES-3 shape (counted repeat of a counted greedy loop); `(?:(?:a+)+){2}` is fine here. Found by cross-checking |
| IRX-XS-5 | XS | unreported | wrong result: `/^(?:a\|^){2}$/.test("a")` → `false`; `/^(?:a\|\B){3}$/.test("aa")` → `false` → expected `true` | not filed | Tested: XS (jsvu, Moddable). a counted group needing a zero-width iteration; `{2,}` is fine. Same family as IRX-JAVA-2, IRX-ONIG-1, IRX-SWIFT-3 |
| IRX-XS-6 | XS | unreported | wrong result: `/^(?:(?:aa(?:)*?){2})*$/.test("aaaaaa")` → `true` → expected `false` | not filed | Tested: XS (jsvu, Moddable). a lazy loop over an empty group inside a counted group miscounts; without `(?:)*?` it is correct. Same shape as one IRX-DOTNET-3 case. Found by cross-checking |
| IRX-XS-7 | XS | unreported | hang: `/(?:a?)*b/.test("a")` and `/(?:a\|)*b/.test("a")` never return; also `/^(?:^a?)+?$/.test("aa")` → expected `false` | not filed | Tested: XS (jsvu, Moddable). a star over a nullable body that fails after it loops forever; `(?:\|a)*b` and `(?:)*b` are fine. Found by cross-checking IRX-BOA-8 |
| IRX-XS-8 | XS | unreported | wrong result / wrong span: `/(?:a\|a){3}/.exec("aa")` → `"aa"`; `/^(?:a\|a){3}$/.test("aa")` → `true`; `/(?:a{2,}){3}/.exec("aaaa")` → `"aaaa"` → expected `null`; `false`; `null` | not filed | Tested: XS (jsvu, Moddable). a counted group over alternatives that can match the same text is satisfied too early; `(?:a\|b){3}` is correct. Found by span mode |
| IRX-XS-9 | XS | unreported | wrong capture: `/(a\|)*c/.exec("ac")` → `["ac", undefined]`; `/(a*)+/.exec("b")` → `["", undefined]` → expected `["ac", "a"]`; `["", ""]` (V8, QuickJS, Boa, Hermes) | not filed | Tested: XS (jsvu, Moddable). when a loop's next iteration is rejected, the captures of the last successful iteration are dropped instead of restored. Found while researching phase 2 ([docs/phase2-captures.md](docs/phase2-captures.md)) |
| IRX-XS-10 | XS | unreported | wrong span: `/(?:\|a)*/.exec("a")` → `[""]`; `/(?:a*?)*/.exec("a")` → `[""]` → expected `["a"]` (V8, QuickJS; ES RepeatMatcher rejects an empty iteration once min is met) | not filed | Tested: XS (jsvu, Moddable). XS accepts the empty iteration and leaves the loop, as Perl/PCRE do, instead of rejecting it and trying the other branch. Found by span mode |
| IRX-E262-1 | engine262 | unreported | rejects valid pattern: `new RegExp("[\u{17F}--\u{212A}]", "v")` → SyntaxError "Expect a CharacterClassEscape" → expected accepted | not filed | Tested: engine262 (npm `@engine262/engine262`). a `\u{…}` escape is not accepted as a `ClassSetOperand` in set operations (~9.7k findings) |
| IRX-E262-2 | engine262 | unreported | wrong result: `/^[^[^a]&&\d]$/v.test("ſ")` → `false`; `/^a[^A&&[a-z]]$/v.test("aa")` → `false` → expected `true`; `true` | not filed | Tested: engine262 (npm `@engine262/engine262`). negated classes whose contents are a set operation are computed wrongly (~46k findings) |
| IRX-HERMES-1 | Hermes | unreported | wrong result: `/^(?:(?:(?:\W+){1,1})*\s)$/.test("\u2028\n")` → `false` → expected `true` | not filed | Tested: Hermes (jsvu). Boa also fails it (cross-check) |
| IRX-HERMES-2 | Hermes | unreported | exception on tiny input: `/^(?:(?:^a?)+?)$/.test("aa")` → `RangeError: Maximum regex stack depth reached` → expected `false` | not filed | Tested: Hermes (jsvu). also `(?:a*)+?\B` on `"a"`, `(?:(?:(?:)\|(?:)){2,2}){1,2}` on `"a"`: lazy loops over empty-matchable bodies recurse without bound |
| IRX-HERMES-3 | Hermes | unreported | wrong result: `/(?:(?:a+){1}){2}/.test("aa")` → `false`; `/^(?:(?:a{2,}){2}){2}$/.test("a".repeat(8))` → `false` → expected `true` | not filed | Tested: Hermes (jsvu). a counted repeat of a group whose body is a counted repeat of a greedy loop; `(?:(?:aa+)(?:aa+)){2}` is fine. Same shape as IRX-BOA-7 |
| IRX-HERMES-4 | Hermes | unreported | wrong result: `/a(?<=x\|^a)/.test("a")` → `false` → expected `true` | not filed | Tested: Hermes (jsvu). `^` inside an alternative of a lookbehind; `a(?<=^a)` and `a(?<=x\|a)` are fine |
| IRX-RACKET-1 | Racket | unreported | crash at construction: `(pregexp "(?:)(?:)")` → `exn:fail` "invalid memory reference. Some debugging context lost" → expected compiles; matches `""` | not filed | Tested: Racket 9.3 CS (`regexp`/`pregexp`/`byte-pregexp`). two or more adjacent empty non-capturing groups (also `a\|(?:)(?:)`, `^(?:(?:)(?:))$`); `()()`, `(?:(?:))`, `(?:)a(?:)` are fine, and a `#rx` literal `x(?:)(?:)y` works. The message is Chez Scheme's memory-fault handler |
| IRX-RACKET-2 | Racket | unreported | wrong result: `(regexp-match? #px"^b(?<=b(?=a))a$" "ba")` → `#f`; `#px"(?<=(?=a))"` never matches; `#px"^(?<!(?!a))a$"` misses `"a"` → expected `#t` | not filed | Tested: Racket 9.3 CS (`#px`). a lookahead inside a lookbehind cannot see past the lookbehind's end position: it runs on the subject cut at that point |
| IRX-LLVM-1 | LLVM | unreported | wrong result (not leftmost): `Regex("(()\|a)b").match("ab", &m)` reports `[1,2)`; `(()\|a)$` on `"a"` reports `[1,1)` → expected `[0,2)`; `[0,1)` | not filed | Tested: LLVM 23.1.2 `llvm::Regex` (BSD/Spencer ERE). a match starting at 0 exists but is skipped when the first alternative can be empty (also `(x*\|a)$`); `(a\|())$` is fine. With REG_NEWLINE it turns full-match checks into misses |
| IRX-LLVM-2 | LLVM | unreported | wrong result: `Regex("(^){2}x").match("x")` → false; `(^){2}` misses `""` → expected true | not filed | Tested: LLVM 23.1.2 `llvm::Regex` (BSD/Spencer ERE). an exact count on a group holding an anchor never matches (`(^){2}`, `($){2}`); `(^)(^)`, `(^){1,2}`, `(^)+` and `(()){2}` are fine |
| IRX-JAVA-1 | Java | resolved | wrong result (asymmetric case folding): `Pattern.compile("ß", CASE_INSENSITIVE \| UNICODE_CASE).matcher("ẞ").matches()` → false → expected true (`Pattern.compile("ẞ", …).matcher("ß")` is true) | not filed | Tested: OpenJDK 23 `java.util.regex` (`CASE_INSENSITIVE \| UNICODE_CASE`). **resolved in current version (OpenJDK 27)**; ß and ẞ now match in both directions, including the class case; older OpenJDK 23 behavior is retained here |
| IRX-JAVA-2 | Java | partly resolved | wrong result: `Pattern.matches("(?:a\|^){2}", "a")` → `false`; also `(?:a\|\B){3}` on `"aa"`, `(?:(?=a)\|a){2}` on `"a"`, `(?:^a*){2}` on `"a"` → expected `true` | not filed | Tested: OpenJDK 23 `java.util.regex`. a counted group where one iteration is a zero-width assertion stops counting; **resolved in current version (OpenJDK 27)** for these recorded variants; JAVA-2 has a different counted-loop form that still fails. In OpenJDK 23 an empty alternative and the unrolled form were correct. Related behavior remains in Ruby/Oniguruma (IRX-ONIG-1), Swift (IRX-SWIFT-3) and XS (IRX-XS-5) |
| IRX-JAVA-3 | Java | unreported | wrong result: `Pattern.compile("(?<=a*a*)").matcher("a").find()` → `false`; `a(?<=a*b*)` misses `"a"` → expected `true` | not filed | Tested: OpenJDK 23 `java.util.regex`. a lookbehind with two unbounded parts never matches (likely overflow of the summed maximum length); `(?<=a*)` and `(?<=a?a*)` are fine |
| IRX-JAVA-4 | Java | unreported | wrong capture: `(?:(a)+){2}` on `"aaa"` → group 1 `[1,2)`; `a{0,}(?=a\|(()))a` on `"a"` → group 1 `[1,1)`; `(?:(?:()a){2}){0,}` on `"a"` → group 1 `[0,0)`; `a()*` on `"a"` → group 1 unset → expected `[2,3)`; unset; unset; `[1,1)` (Python, PCRE2) | not filed | Tested: OpenJDK 23 `java.util.regex`. captures inside loops are not kept in step with backtracking: values from abandoned attempts survive, and the iteration that actually completed is not the one recorded. Found by capture mode (phase 2) |
| IRX-ICU-1 | ICU | unreported | hang: `NSRegularExpression(pattern: "a(?:)*?b").firstMatch(in: "ac", …)` never returns; also `a(?:\b)*?b` on `"a b"`, `a(?:(?=c))*?b` on `"ac"`, `.(?:$)*?.` on `"k\n"` with `anchorsMatchLines` → expected `nil` | not filed | Tested: ICU regex (macOS 27 `libicucore`, via `NSRegularExpression`). a lazy unbounded loop (`*?`, `+?`) whose body matches empty, when what follows fails; greedy `*` and bounded `{0,3}?` are fine. Every 10-minute ICU batch hit one; also hangs on `(?:^a?)+?` vs `"aa"` (the IRX-HERMES-2 shape) and `(?:(?:aa(?:)*?){2})*` |
| IRX-ONIG-1 | Onigmo / Oniguruma | unreported | wrong result: `/\A(?:^a*){2,3}\z/.match?("a")` → `false`; Ruby also: `\A(?:a\|^){2,3}\z` on `"a"`, `\A(?:\B\|a){3}\z` on `"aa"`; Oniguruma also: `\A(?:^a{0,2}){2}\z` → expected `true` | not filed | Tested: Ruby 4.0.7 (Onigmo) and Oniguruma 6.9.10. a counted group needing a zero-width iteration (`^`, `\B`, or a body that gives back its characters) to reach its count. Ruby's `\A(?:a\|^){2}\z` is fine but `{2,3}` is not. Same idea as IRX-JAVA-2 (Oniguruma rejects quantified bare anchors outright) |
| IRX-RUBY-1 | Ruby | unreported | wrong result: `/\A(?:a(?:()\|a){3,}){2}\z/.match?("aa")` → `false`; `/\A(?:(?:()\|()){3,}a){0,3}\z/.match?("aaa")` → `false` → expected `true` | not filed | Tested: Ruby 4.0.7 (Onigmo). an empty **capture** as a branch of a `{3,}` loop inside a counted group. The same patterns with `(?:)` instead of `()` match, as does `{2,}`; Oniguruma 6.9.10 is correct. Found by the new empty-atom spellings. Simpler: `/\A(?:(){1,2}?a)+\z/.match?("aa")` → `false` (true with `(?:)`, with a greedy `{1,2}`, or on `"a"`) |
| IRX-RE2-1 | RE2 | unreported | wrong result: `RE2::FullMatch("ſ", "a\|[sS]")` → `true`; `b\|[kK]` matches `"K"` (U+212A) → expected `false` | not filed | Tested: RE2 2025-11-05 (Homebrew; C++). no `i` flag: merging the alternatives into one class appears to add the case-fold partners of `s`/`k` (U+017F, U+212A). `[sS]` alone and `a\|s\|S` are correct; Go's `regexp` is correct |
| IRX-RE2-2 | RE2 | unreported | wrong span (mid-character): `RE2("\\B").Match("aé", 0, 3, UNANCHORED, &m, 1)` → `[2,2)`, between the two bytes of `é`; same for `Σ` → expected `[3,3)` (end of string) | not filed | Tested: RE2 2025-11-05 (Homebrew; C++). `\B` treats the bytes of a multi-byte UTF-8 character as non-word characters, so an empty match can start inside one. Go's `regexp` is correct. Found by span mode |
| IRX-RESHARP-1 | RE# | unreported | wrong result: `\A(?:a(?=b)?(?:bc)?)\z` matches `"ab"`; also `\A(?:a(?:c\|(?=b))(?:c\|(?=b)))\z` → expected no match | not filed | Tested: RE# (`resharp` 0.7.5, Rust). still reproduces on upstream main `28a7446de29f` (2026-09-17); an optional or alternated lookahead followed by more pattern accepts a character nothing consumes; `a(?=b)(?:bc)?` (lookahead not optional) is correct |
| IRX-EMACS-1 | Emacs | unreported | crash (SIGABRT): `emacs -Q --batch -l hosts/emacs/host.el shell < docs/repros/IRX-EMACS-1.jsonl` → `abort()` in `forall_firstchar_1` ← `regex_compile` ← `string_match_1`, while compiling the translation of `[aσ]\|(?:-\|\B)[😀İ](?:)(?:[a-c]\|^)\|(?:\b)?\|(?:\w*?)*\|$` → expected compiles | not filed | Tested: GNU Emacs 31.1 (Homebrew, native-comp). deterministic with the recorded 10-pattern batch (each pattern is needed). Compiling that pattern alone, or replaying the same `string-match` calls without the host's JSON work, does not abort, so it looks like stale or uninitialized state in the compiler (8 batches in 10 minutes) |
### Imported from regex_comparison

<!-- regex engine bugs: 43, structural: 15 -->
| ID | Engine | Status | Kind | Upstream report | Summary |
|---|---|---|---|---|---|
| [JSC-1](../regex_comparison/bugs/BUGS.md#jsc-1) | JavaScriptCore (Bun) | ✅ fixed | wrong result | not filed | `/u` class with an ASCII range + astral range misses astral chars after index 0 |
| [JSC-2](../regex_comparison/bugs/BUGS.md#jsc-2) | JavaScriptCore (Bun) | ✅ fixed | wrong result | not filed | `(?:^)?` / `(?:^)*` makes the match fail when it doesn't start at index 0 |
| [JAVA-1](../regex_comparison/bugs/BUGS.md#java-1) | java.util.regex | ❌ open | wrong result | not filed | lookbehind never matches an *escaped* supplementary code point |
| [PERL-1](../regex_comparison/bugs/BUGS.md#perl-1) | Perl | ❌ open | wrong result | [#24915](https://github.com/Perl/perl5/issues/24915) | `(?:b{2}){2}` after any `+`/`*` quantifier fails: `/x+(?:b{2}){2}/` misses `"xxbbbb"` |
| [DOTNET-1](../regex_comparison/bugs/BUGS.md#dotnet-1) | .NET Regex (interpreter) | ✅ fixed in .NET 11 RC 1 (still in 10.0.12), filed [#135328](https://github.com/dotnet/runtime/issues/135328) | **hang** | [#135328](https://github.com/dotnet/runtime/issues/135328) | `(?:\|a?\|b)+?c` on `"a"` never terminates (the two-branch form was fixed in .NET 10) |
| [SWIFT-1](../regex_comparison/bugs/BUGS.md#swift-1) | Swift Regex | ❌ open | rejects valid pattern | [#750](https://github.com/swiftlang/swift-experimental-string-processing/issues/750) | range endpoints that aren't NFC-stable are rejected |
| [SWIFT-2](../regex_comparison/bugs/BUGS.md#swift-2) | Swift Regex | ❌ open | wrong captures | not filed | a group quantified `{0}` (never run) reports an empty capture instead of nil: `"ab".firstMatch(of: /(a){0}(b)/)!.1` is `""` at 1 |
| [SWIFT-PERF-1](../regex_comparison/bugs/BUGS.md#swift-perf-1) | Swift Regex | ❌ open | **hang** | [#894](https://github.com/swiftlang/swift-experimental-string-processing/issues/894) | `(?:.b\|)+.` never returns, even on `"a"` or `""` (minimized 2026-10-07; originally seen as a >5 min match) |
| [NIM-1](../regex_comparison/bugs/BUGS.md#nim-1) | nim-regex | ❌ open | **crash** or wrong result | [#169](https://github.com/nitely/nim-regex/issues/169), [#170](https://github.com/nitely/nim-regex/issues/170) | `{m,n}` around a lookaround aborts the compiler with an `AssertionDefect`; inside an optional group it compiles and silently misses matches |
| [NIM-3](../regex_comparison/bugs/BUGS.md#nim-3) | nim-regex | ❌ open | **segfault** | [#166](https://github.com/nitely/nim-regex/issues/166) | `re2("a?(?:b?)*c")` crashes the process (SIGSEGV) while compiling |
| [NIM-4](../regex_comparison/bugs/BUGS.md#nim-4) | nim-regex | ❌ open | **performance (compile-time DoS)** | [#167](https://github.com/nitely/nim-regex/issues/167) | `re2("(?:\|y\|()){22}")` takes ~12 s to compile, and each +1 on the count costs ×2.4 |
| [PERL-3](../regex_comparison/bugs/BUGS.md#perl-3) | Perl | ❌ open | wrong span | [#24926](https://github.com/Perl/perl5/issues/24926) | `"aaaa" =~ /(?:x??\x{100})*a+/` matches `"a"`: a greedy quantifier after a starred group with a lazy optional and a char above U+00FF matches as few times as possible |
| [PERL-2](../regex_comparison/bugs/BUGS.md#perl-2) | Perl | ❌ open | wrong result | [#24916](https://github.com/Perl/perl5/issues/24916) | `"àéàj" =~ /à+j/` misses: Latin-1 char repeated with `+` on a UTF-8 string, when another Latin-1 char sits between runs |
| [EMACS-1](../regex_comparison/bugs/BUGS.md#emacs-1) | Emacs `rx` | ❌ open | wrong result | not filed | `(rx (? bos) "a")` is `` "\\`?a" ``, where Emacs reads the `?` as a literal: it matches `"?a"` but not `"a"`. `rx` brackets `bol` but not `bos` |
| [RACKET-1](../regex_comparison/bugs/BUGS.md#racket-1) | Racket regexps (`#rx`/`#px`) | ❌ open | wrong result | not filed | character ranges lose part of their middle: `#px"[І-Ӱ]"` (U+0406–U+04F0) doesn't match `"э"` (U+044D); about 5% of random ranges are affected |
| [RACKET-2](../regex_comparison/bugs/BUGS.md#racket-2) | Racket regexps (`#px`) | ❌ open | wrong result | not filed | a negative lookbehind that can match characters of different UTF-8 lengths succeeds wrongly: `#px"(?<!.)x"` and `#px"(?<![aé])x"` match `"éx"` |
| [RACKET-3](../regex_comparison/bugs/BUGS.md#racket-3) | Racket regexps (`#px`/`#rx`) | ❌ open | wrong result, invalid span | not filed | a match made only of zero-width assertions can start inside a multi-byte char: `(regexp-match? #px"(?!é)(?!$)" "éé")` is `#t`; on a port the match is at byte 1, mid-`é` |
| [RHOMBUS-1](../regex_comparison/bugs/BUGS.md#rhombus-1) | Rhombus `rx` | ❌ open | wrong result | not filed | a `]` in a charset, alone or inside a range, is never matched: `rx'["]" "a"]'` compiles to `#px"^[[a]$"`, `rx'["["-"^"]'` to `#px"^[[\\[^]$"` |
| [RHOMBUS-2](../regex_comparison/bugs/BUGS.md#rhombus-2) | Rhombus `rx` | ❌ open | wrong result | not filed | charsets with a range spanning the surrogates lose U+E000–U+FFFF: `rx'["?"-"\U0010FFFF"]'`, `rx'[! "a"]'` and a 797-range `\W` class don't match `"\uFFFD"`/`"﷏"` |
| [RHOMBUS-3](../regex_comparison/bugs/BUGS.md#rhombus-3) | Rhombus `rx` | ❌ open | wrong result | not filed | an alternation whose branches are all empty loses its group: `rx'"b" ("" \|\| "") "C"'` compiles to `#px"^(?:(?:b\|)C)$"` and matches `"C"` |
| [NIM-6](../regex_comparison/bugs/BUGS.md#nim-6) | nim-regex | ❌ open | wrong result | not filed | `{0}` acts as `{1}`: `"xa".find(re2"xa{0}")` matches `"xa"`, `^(a){0}$` misses `""`, `(a){0}b` misses `"b"` |
| [NIM-7](../regex_comparison/bugs/BUGS.md#nim-7) | nim-regex | ❌ open | wrong captures | not filed | in a lazy bounded loop `{m,n}?`, one long iteration beats two short ones: `"a@x,@y,7".find(re2"a(@.+?,){0,5}?7")` gives group 1 = `"@x,@y,"`, expected `"@y,"` |
| [NIM-5](../regex_comparison/bugs/BUGS.md#nim-5) | nim-regex | ✅ passes on upstream main `b0b76981aedb` (unreleased) | wrong span | not filed | `"ab".find(re2"a??b")` reports a match starting at 1, not the leftmost 0: a lazy or empty-first choice at the start makes `find` prefer a later start. `contains` is correct |
| [NIM-2](../regex_comparison/bugs/BUGS.md#nim-2) | nim-regex | ❌ open | wrong result | [#168](https://github.com/nitely/nim-regex/issues/168) | `(?<=a)aa` misses `"aaa"`: after a lookbehind rejects one occurrence of a literal, overlapping occurrences are skipped |
| [DOTNET-4](../regex_comparison/bugs/BUGS.md#dotnet-4) | .NET Regex (all 3 engines) | ❌ open (still in 11 RC 1), filed [#135329](https://github.com/dotnet/runtime/issues/135329) | wrong result | [#135329](https://github.com/dotnet/runtime/issues/135329) | `(?:a+\|){5}` doesn't match `"aaaa"` (it can match `""`!); `(?:a+\|){2}d` misses `"ad"`. Interpreter, Compiled and NonBacktracking all wrong |
| [JAVA-3](../regex_comparison/bugs/BUGS.md#java-3) | java.util.regex | ❌ open | **invalid span** | not filed | iterating `find()` over `"a😀b"` with an empty-matching pattern reports an empty match at UTF-16 index 2, *inside* the emoji's surrogate pair |
| [JAVA-4](../regex_comparison/bugs/BUGS.md#java-4) | java.util.regex | ❌ open, already reported as [JDK-8187080](https://bugs.openjdk.org/browse/JDK-8187080) | wrong captures | [JDK-8187080](https://bugs.openjdk.org/browse/JDK-8187080) | `(?:(.))+\d` on `"ab5"` gives group 1 = `"5"`, a value from a loop iteration that backtracking undid; expected `"b"` |
| [JAVA-2](../regex_comparison/bugs/BUGS.md#java-2) | java.util.regex | ❌ open | wrong result | not filed | `(?:u\|\b){3}d` misses `"uud"`: a zero-width iteration can't count toward a loop minimum |
| [RUBY-1](../regex_comparison/bugs/BUGS.md#ruby-1) | Onigmo (Ruby) | ❌ open | wrong result | [#22418](https://bugs.ruby-lang.org/issues/22418) | same as JAVA-2: `(?:u\|\b){3}d` misses `"uud"` |
| [RUBY-2](../regex_comparison/bugs/BUGS.md#ruby-2) | Onigmo (Ruby) | ❌ open | wrong result | [bugs.ruby-lang.org](https://bugs.ruby-lang.org/issues/22418) | `(?:a(?:()\|b){1,3}){2}` misses `"aa"`: a `{m,n}` loop (n ≥ 3) over an empty capture group or `b`, inside an outer loop, won't take the empty branch again; `{1,2}` and a plain empty branch are right |
| [DOTNET-3](../regex_comparison/bugs/BUGS.md#dotnet-3) | .NET Regex (interpreter) | ✅ fixed in .NET 11 RC 1 (still in 10.0.12), filed [#135330](https://github.com/dotnet/runtime/issues/135330) | wrong result | [#135330](https://github.com/dotnet/runtime/issues/135330) | `(?:(?:\|,)(?:w\|)+?7){3}z` misses `"7,7,7z"`: exact repeat containing a lazy possibly-empty loop; Compiled is correct |
| [DOTNET-5](../regex_comparison/bugs/BUGS.md#dotnet-5) | .NET Regex (interpreter) | ✅ fixed in .NET 11 RC 1 (still in 10.0.12), filed [#135331](https://github.com/dotnet/runtime/issues/135331) | **wrong result, invalid span** | [#135331](https://github.com/dotnet/runtime/issues/135331) | `(?:(?:a\|)+?b){2}` "matches" `"ab"` at Index=2, Length=1 (past the end of the string); `.Value` throws, `Replace` crashes |
| [V8-1](../regex_comparison/bugs/BUGS.md#v8-1) | V8 (Node, Deno) | ❌ open, **partially fixed** | wrong result | [#572331419](https://issues.chromium.org/issues/572331419) (mapping inferred from filing order) | `/[^a]$/u.test("😀")` is fixed in Chrome 155, but `/[\u{10000}-\u{10FFFF}]$/u.test("\u{115D3}")` still fails there. Node 26 reproduces both |
| [V8-3](../regex_comparison/bugs/BUGS.md#v8-3) | V8 (Node, Deno) | ❌ open, **regression** | wrong result | [#571450188](https://issues.chromium.org/issues/571450188) | `/[\s\S]*?x^\|/.test("")` is false: a lazy match-anything class, a literal and `^` sink the whole regex. Node 25 is correct |
| [V8-2](../regex_comparison/bugs/BUGS.md#v8-2) | V8 (Node, Deno) | ✅ resolved in Chrome 155; older V8 still affected | wrong result | not filed | with `/u` or `/v`, V8 tried match positions inside surrogate pairs; all six recorded cases pass in Chrome 155 |
| [ICU-1](../regex_comparison/bugs/BUGS.md#icu-1) | ICU (`NSRegularExpression`) | ❌ open | wrong result | not filed | `(?:X*?)+?Y` doesn't match `"XY"`: a lazy loop over a lazy, possibly-empty body gives up |
| [ICU-2](../regex_comparison/bugs/BUGS.md#icu-2) | ICU (`NSRegularExpression`) | ❌ open | **hang** | not filed | `(?:a*)*?;b` on `";c"` never terminates |
| [DOTNET-6](../regex_comparison/bugs/BUGS.md#dotnet-6) | .NET Regex (all 3 engines) | ❌ open | wrong span | [#135584](https://github.com/dotnet/runtime/issues/135584) | `Regex.Match("aaba", "(?:(?:ab??)+){2}")` is `"aa"`; backtracking semantics (PCRE, Perl, Python, Java) and Rust/Go give `"aaba"`. A greedy loop nested in a counted loop, with a lazy optional at the end of the body |
| [DOTNET-2](../regex_comparison/bugs/BUGS.md#dotnet-2) | .NET Regex (NonBacktracking) | ✅ fixed in .NET 11 RC 1 (still in 10.0.12), filed [#135332](https://github.com/dotnet/runtime/issues/135332) | wrong result | [#135332](https://github.com/dotnet/runtime/issues/135332) | misses real matches once the pattern has ≥ 256 distinct character sets; 255 works |
| [ICU-3](../regex_comparison/bugs/BUGS.md#icu-3) | ICU (`NSRegularExpression`) | ❌ open | wrong result | not filed | `(?:(?:C*)+?x)?` returns false on `""`: a failing lazy loop over a possibly-empty body at end of input aborts the whole match, skipping alternatives |
| [HS-1](../regex_comparison/bugs/BUGS.md#hs-1) | Hyperscan (Vectorscan) | ❌ open | wrong result | not filed | with `HS_FLAG_UTF8`, `(?:[^é]+)+.c` matches `"aééc"`: a repeated group splits a multi-byte character |
| [RESHARP-1](../regex_comparison/bugs/BUGS.md#resharp-1) | RE# (`resharp` crate) | ❌ open | wrong result | [#32](https://github.com/ieviev/resharp/issues/32) | zero-width matches are reported *inside* multi-byte UTF-8 characters: `\B` matches `"é"` (at byte 1), and so does `(?<!é)(?!é)` |
| [RUST-PERF-1](../regex_comparison/bugs/BUGS.md#rust-perf-1) | Rust `regex::bytes::Regex::find_iter` | 📘 documented behavior | quadratic iteration | not filed | `(?:a(\w+[A-Z])y)\|.` on long `a` runs takes ~4× longer when input doubles |

#### Structural matchers (CSS selectors, DOM, FileCheck, macros, ISel)

| ID | Engine | Status | Kind | Upstream report | Summary |
|---|---|---|---|---|---|
| [LOLHTML-1](../regex_comparison/bugs/BUGS.md#lolhtml-1) | lol-html (Bun `HTMLRewriter`) | ❌ open | wrong result (CSS) | not filed | `[a^=""]` and `[a$=""]` match every element whose `a` is non-empty, and `[a~=""]` matches `a=""` or values with leading, trailing or doubled spaces; by spec an empty value matches nothing (`[a*=""]` is right) |
| [SOUPSIEVE-1](../regex_comparison/bugs/BUGS.md#soupsieve-1) | soupsieve (Beautiful Soup) | ❌ open | wrong result (CSS) | not filed | the `BeautifulSoup` document object counts as an element: `* > *` and `* > r` match the root element |
| [LEXBOR-1](../regex_comparison/bugs/BUGS.md#lexbor-1) | Lexbor (selectolax, C) | ❌ open | wrong result (CSS) | not filed | after `:is()`/`:where()`/`:not()`, `~` acts like `+`: `div > :is(y) ~ *` finds only the next sibling (`div > y ~ *` is right) |
| [JSDOM-1](../regex_comparison/bugs/BUGS.md#jsdom-1) | jsdom (`@asamuzakjp/dom-selector`) | ❌ open | wrong result (CSS) | not filed | `[a\|=""]` matches nothing; browsers match `a=""` and `a="-x"` |
| [CSSSELECT-1](../regex_comparison/bugs/BUGS.md#cssselect-1) | css-select (cheerio, linkedom) | ❌ open | wrong result (CSS) | not filed | `[a~=""]` matches `a=""` and values with leading, trailing or doubled spaces, like LOLHTML-1 |
| [LINKEDOM-1](../regex_comparison/bugs/BUGS.md#linkedom-1) | linkedom | ❌ open | wrong result (DOM, CSS) | not filed | the class attribute is normalized: `getAttribute("class")` trims `" ab"` to `"ab"` and returns `""` when absent, so `[class=" "]` and `[class^=" a"]` miss |
| [HAPPYDOM-1](../regex_comparison/bugs/BUGS.md#happydom-1) | happy-dom | ❌ open | wrong result (CSS) | not filed | `a ~ b` finds only the first matching later sibling; `a ~ * ~ *` finds nothing |
| [HAPPYDOM-2](../regex_comparison/bugs/BUGS.md#happydom-2) | happy-dom | ❌ open | wrong result (CSS) | not filed | `[a^=""]`, `[a$=""]`, `[a~=""]` match `a=""`; `[a\|=""]` misses `a="-x"` |
| [HAPPYDOM-3](../regex_comparison/bugs/BUGS.md#happydom-3) | happy-dom | ❌ open | wrong result (CSS) | not filed | a plain pseudo-class between two functional ones is dropped: `r > :not(c):first-child:nth-child(2)` and `r > :nth-child(2):first-child:not(c)` match the 2nd child |
| [HAPPYDOM-4](../regex_comparison/bugs/BUGS.md#happydom-4) | happy-dom | ❌ open | wrong result (CSS) | not filed | `[p~="a b"]` matches `p="a b"`; a `~=` value containing whitespace must match nothing |
| [LLVM-GISEL-1](../regex_comparison/bugs/BUGS.md#llvm-gisel-1) | LLVM AArch64 GlobalISel | ❌ open | fails to compile (only with fallback disabled) | not filed | `zext <4 x i13> %x to <4 x i128>` then `extractelement`: "cannot select: G_MERGE_VALUES gpr(i16) ×4 → gpr64"; by default it silently falls back to SelectionDAG |
| [CHIBI-1](../regex_comparison/bugs/BUGS.md#chibi-1) | Chibi Scheme `syntax-rules` | ❌ open | wrong result (macro matching) | not filed | a literal under `...` isn't checked: with literal `b`, `(_ b ...)` matches `(m c)` and `(m b (c))` |
| [PYFILECHECK-1](../regex_comparison/bugs/BUGS.md#pyfilecheck-1) | filecheck (Python FileCheck clone) | ❌ open | wrong result (FileCheck) | not filed | `CHECK-NEXT` skips the rest of the previous match's line: `CHECK: bbb` / `CHECK-NEXT: a` passes on `xbbba\na`; LLVM fails it |
| [PYFILECHECK-2](../regex_comparison/bugs/BUGS.md#pyfilecheck-2) | filecheck (Python FileCheck clone) | ❌ open | wrong result (FileCheck) | not filed | `CHECK-NOT` matches that overlap the next match count: `CHECK-NOT: cb` / `CHECK: bx` fails on `cbx`; LLVM passes. Likely the cause of upstream #10 |
| [SOUPSIEVE-2](../regex_comparison/bugs/BUGS.md#soupsieve-2) | soupsieve (Beautiful Soup) | ❌ open | wrong result (CSS) | not filed | `:has(~ X)` is wrong: on `<a/><b/><c/>`, `div > :has(~ b)` selects a and c (Chrome: a) |

## Fuzzer plan: one inverted-pair fuzzer per dialect

Every regex target in `../regex_comparison` has a directory `targets/<name>/` (engine command, dialect,
config overlay, results) and has had a 1-minute smoke campaign (`tools/irx_target.py`). A host speaks the line protocol (`driver.js`, `driver.pl`, `tools/bridge.py` or a
program under `hosts/`). The **model** column says which semantics the oracle uses; "Perl model" on a
non-Perl engine means its own dialect model is not written yet, so smoke-run mismatches there are mostly
dialect gaps rather than bugs. Structural matchers (CSS, DOM, FileCheck, macros, ISel) are out of scope.

| Target | Directory | Host | Model | Status |
|---|---|---|---|---|
| V8 15.5 (d8) | [`v8`](targets/v8) | `driver.js` | ES2024 (exact) | IRX-V8-1…4 |
| QuickJS | [`quickjs`](targets/quickjs) | `driver.js` (std) | ES2024 | IRX-QJS-1 |
| XS | [`xs`](targets/xs) | bridge | ES2024 | IRX-XS-1…10 |
| Boa | [`boa`](targets/boa) | bridge | ES2024 | IRX-BOA-1…8 |
| engine262 | [`engine262`](targets/engine262) | bridge | ES2024 | IRX-E262-1, 2 |
| Hermes | [`hermes`](targets/hermes) | bridge | ES2024 minus `v` | IRX-HERMES-1…4 |
| JavaScriptCore (Bun 1.4.2) | [`bun`](targets/bun) | `driver.js` (node adapter) | ES2024 | clean (0 self-check mismatches) |
| V8 14.1 / 15.0 (Node, Deno) | [`node`](targets/node), [`deno`](targets/deno) | `driver.js` | ES2024 | older V8; excluded from the ledger |
| Perl 5.44 / blead | [`perl`](targets/perl) | `driver.pl` | Perl `/u` (exact) | IRX-PERL-1…3 |
| PCRE2 10.49 | [`pcre2`](targets/pcre2) | `hosts/c/pcre2_host` | Perl (exact) | IRX-PCRE2-1, 3 (JIT), IRX-PCRE2-2 |
| PHP 8.5 `preg_*` | [`php-pcre2`](targets/php-pcre2) | `hosts/script/php_host.php` | Perl (exact) | IRX-PCRE2-1…3 |
| Swift Regex 6.4 | [`swift-regex`](targets/swift-regex) | `hosts/swift` (scalar semantics) | Swift (exact) | IRX-SWIFT-1…3 |
| .NET 9 interpreter / Compiled / NonBacktracking | [`dotnet-interp`](targets/dotnet-interp), [`dotnet-compiled`](targets/dotnet-compiled), [`dotnet-nonbacktracking`](targets/dotnet-nonbacktracking) | `hosts/dotnet` | `dotnet` / `dotnet-nonbacktracking`: UTF-16 units, `\w` = L\|Mn\|Nd\|Pc (exact) | IRX-DOTNET-1…8 |
| ICU (`NSRegularExpression`) | [`icu`](targets/icu) | `hosts/swift` | `icu`: UTS #18 classes, Unicode line ends, CRLF `$` (exact) | IRX-ICU-1 |
| Rust `regex` | [`rust-regex`](targets/rust-regex) | `hosts/rust` | `rust` (exact) | 0 self-check mismatches; 1.2M patterns, 0 findings |
| fancy-regex | [`fancy-regex`](targets/fancy-regex) | `hosts/rust` | `fancy`: fixed-length lookbehind, no empty-body quantifiers (exact) | 0 self-check mismatches |
| RE# (`resharp`) | [`resharp`](targets/resharp) | `hosts/rust` | `resharp`: UnicodeMode::Full; no lazy, lookbehind, mid-pattern `^`/`\b`, lookahead under `*` (exact) | 0 self-check mismatches; named groups under quantifiers rejected; IRX-RESHARP-1 |
| RE2 | [`re2`](targets/re2) | `hosts/c/re2_host` | `re2`: ASCII classes (exact) | IRX-RE2-1, 2 |
| Go `regexp` | [`go-regexp`](targets/go-regexp) | `hosts/go` | `go`: ASCII classes (exact) | 0 self-check mismatches |
| Oniguruma 6.9 | [`oniguruma`](targets/oniguruma) | `hosts/c/onig_host` | `oniguruma`: Unicode classes, Ruby anchors (exact) | IRX-ONIG-1 |
| Ruby Onigmo | [`ruby-onigmo`](targets/ruby-onigmo) | `hosts/script/rb_host.rb` | `ruby`: ASCII `\w`, Unicode `\b`, always-on line anchors (exact) | IRX-ONIG-1, IRX-RUBY-1 |
| Python `re` | [`python-re`](targets/python-re) | `hosts/script/py_host.py` | `python`: isalnum `\w`, sre case groups, `(?P<…>)` (exact) | 0 self-check mismatches |
| Java `java.util.regex` | [`java`](targets/java) | `hosts/java` | `java`: Java line ends, `lower(upper())` fold, range rule (exact) | IRX-JAVA-1…4 |
| nim-regex | [`nim-regex`](targets/nim-regex) | `hosts/nim` | `nim`: `(?P<…>)`, end-only `$`, case partners in ranges (exact) | NIM-1, NIM-3, NIM-6 rediscovered |
| Tcl ARE | [`tcl`](targets/tcl) | `hosts/script/tcl_host.tcl` | `tcl`: `\y`, L\|Nd\|Pc words, `-linestop` negations, {p, upper, lower} nocase (exact) | IRX-TCL-1 |
| Racket `#px` | [`racket`](targets/racket) | `hosts/racket` | `racket`: ASCII classes, multi-mode `.`, asymmetric fold, `?`-only nullable quantifiers (exact) | IRX-RACKET-1, 2; RACKET-1…3 rediscovered (RACKET-3 by span mode) |
| Emacs Lisp | [`emacs`](targets/emacs) | `hosts/emacs` (translator) | `emacs`: dumped syntax/script/case tables, edge and script-change `\b` (exact) | IRX-EMACS-1 |
| Vectorscan (Hyperscan) | [`vectorscan`](targets/vectorscan) | `hosts/c/hs_host` | `vectorscan`: UCP classes, no anchors or `\b` (exact) | 0 self-check mismatches; ~70 ms per compile |
| LLVM `Regex` (POSIX ERE) | [`llvm-regex`](targets/llvm-regex) | `hosts/c/llvm_host` (translator) | `llvm`: ASCII-only model of a byte engine (exact) | IRX-LLVM-1, 2 |
| Rhombus `rx`, Emacs `rx` | — | — | — | DSL front-ends: need a DSL printer, deferred |

<!-- END shared bug ledger -->

