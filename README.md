# irx — inverted-pair regex fuzzer

irx tests regex engines against a model instead of against each other. Each test table starts from an accept
string A and a reject string R. irx builds a grammar over pairs of span relations on A and R and samples
regexes that match all of A and none of R *according to its model of the engine's semantics*, so every
pattern comes with its own expected answer and a bug shows up even when every engine shares it. A
disagreement means the engine or the model is wrong: triage minimizes the case, and every ledger entry is
confirmed by hand, usually against other engines too.

### Confirmed findings

The [bug ledger](#bug-ledger) has **121 confirmed bug IDs**, **86 unique reported bugs**
(distinct upstream issue links), **112 distinct bug shapes**, and **76 candidates**
still to audit or report. Bug IDs count
separate ledger rows, including confirmed repros linked to an existing report.
Unique bugs count each upstream issue once; shapes group the same failure pattern
even across engines. Findings with no report or confirmed link to one are excluded.
Fixed reported bugs remain in these all-time counts.
Candidates are 53 open, unreported IDs and IRX-JAVA-2, whose recorded examples
were fixed but a different counted-loop form still fails in current OpenJDK.
Resolved, documented, and older-version-only unreported findings are excluded
from the candidate count.

| Engine | Bug IDs | Unique issues | Shapes in engine |
|---|---:|---:|---:|
| XS | 10 | 10 | 10 |
| Boa | 8 | 8 | 8 |
| .NET | 9 | 8 | 8 |
| Perl | 8 | 7 | 7 |
| nim-regex | 6 | 7 | 7 |
| Swift Regex | 6 | 6 | 6 |
| V8 | 6 | 4 | 4 |
| Racket | 6 | 6 | 6 |
| Hermes | 4 | 4 | 4 |
| happy-dom | 4 | 4 | 4 |
| soupsieve | 2 | 2 | 2 |
| jsdom (dom-selector) | 1 | 1 | 1 |
| lol-html | 1 | 1 | 1 |
| Lexbor | 1 | 1 | 1 |
| css-select | 1 | 1 | 1 |
| linkedom | 1 | 1 | 1 |
| Tcl | 1 | 1 | 1 |
| Chibi | 1 | 1 | 1 |
| engine262 | 3 | 3 | 3 |
| Ruby | 4 | 3 | 3 |
| Java | 1 | 1 | 1 |
| RE# | 2 | 2 | 2 |
| QuickJS | 1 | 1 | 1 |
| PCRE2 | 1 | 1 | 1 |
| RE2 | 2 | 2 | 2 |
| Shared shapes across engines | — | — | −5 |
| **Total** | **90** | **86** | **81** |

IRX-V8-1 maps to V8-3's report, IRX-V8-4 to IRX-V8-3's report, and
IRX-PERL-5 to PERL-3's report. DOTNET-8 and DOTNET-6 also share a report and shape;
RUBY-1 and RUBY-2 are different shapes in one report. NIM-1 is one ledger ID
with two separately reported shapes ([#169](https://github.com/nitely/nim-regex/issues/169)
and [#170](https://github.com/nitely/nim-regex/issues/170)).
The cross-engine shape overlaps are BOA-7/XS-4/HERMES-3, BOA-8/XS-7, and
SWIFT-3/XS-5/RUBY-1.

For the remaining JavaScript-engine reports (checked 2026-10-11): engine262's
installed npm package is at upstream `main` commit `678c2c0`, so no source
rebuild is needed. Homebrew QuickJS 2026-06-04 is older than upstream source;
the current source build at `9d01a96` fixes IRX-QJS-1. The Hermes CLI from
GitHub's latest tagged release, v0.13.0, is a 2024 build (and prints 0.12.0).
All four Hermes findings also reproduce in a source build from the current
`260318099.0.0-stable` branch at `09d3bf2` (2026-10-08; CLI prints 1.0.0),
so no further rebuild is needed before filing them.
The jsvu XS binary reports 17.9.3; a rebuild from current Moddable `public`
source at `5f215f7` also reports 17.9.3 and reproduces IRX-XS-11 (filed as #1761).
IRX-XS-3 was a harness artifact, not an XS bug: see its ledger row.

For each case irx checks:

* **Full match**: does the pattern match all of A and none of R? (expected answer from the model)
* **Match position**: the `[start, end)` of an unanchored search's first match in A and R, against a reference
  backtracking matcher (leftmost-longest for the POSIX engines).
* **Capture groups**: the whole match and groups 1–6 from the same reference matcher, with per-engine rules for
  captures inside loops and lookbehinds.
* **Start offsets**: the match position of a search that starts at a random character boundary (`lastIndex`,
  `pos`, a start offset), with the text before it still visible to lookbehind and `\b`.
* **Long inputs**: A is pumped out to 64–4,096 characters by repeating segments the pattern's loops can
  match, and paired with a near-miss long reject (one edit at the start, middle, end or a power-of-two
  boundary). Full match, match position and capture groups are checked on the long pair against a bit-vector
  evaluation of the model that stays exact at any length.

It drives 32 targets covering about 25 engines: V8 (d8, Node, Deno, Bun), QuickJS, Boa, Hermes, XS,
engine262, Perl, PCRE2 (and PHP), Python `re`, Ruby (Onigmo), Oniguruma, Java, .NET (interpreter,
Compiled, NonBacktracking), ICU, Swift Regex, Rust `regex`, fancy-regex, RE#, Go, RE2, nim-regex, Racket,
Tcl, Emacs, Vectorscan and LLVM Regex. Each engine family has its own semantic model (a *dialect*), checked
against the engine by a self-check at startup, and each target is a small `target.toml`. Runs are
deterministic: any case can be regenerated from the run's seed. The original single-engine design for d8 is
[`spec.md`](spec.md); everything since generalizes it. Bugs found so far are in the [bug ledger](#bug-ledger).

## Quick start

Requires Zig 0.16.0 (`.zigversion`); macOS on Apple Silicon is the primary platform (POSIX/Darwin APIs
only). Engines come from Homebrew, jsvu, cargo, npm and the system (see each `targets/<name>/target.toml`).

```sh
zig build test                        # unit tests (Debug, safety checks on)
zig build -Doptimize=ReleaseFast      # campaign build -> zig-out/bin/irx
hosts/build.sh                        # build the native protocol hosts into hosts/bin/
tools/irx_target.py pcre2 --duration 300          # one engine for 5 minutes
tools/irx_target.py --all --duration 600          # every target, 10 minutes each
tools/irx_target.py bun --long --duration 600     # long-input campaign (only the long mode)
```

`tools/irx_target.py` merges `weights.toml` with the target's overlay, runs irx, writes
`findings/<label>-<target>/`, and refreshes the results block in `targets/<target>/README.md`
(`--no-readme` to skip, `--no-selfcheck` to skip the startup self-check, `--label` to name the run).

## What each case checks

Every batch of cases goes to one engine process per *mode*; a target enables the modes it supports.

| Mode | Host is asked | Expected answer from |
|---|---|---|
| full match (`shell`, `perl`, d8 `interp`/`native`) | does the pattern fully match A? R? | the relation model (exact, by construction) |
| repeat (`shell-repeat`, `perl-repeat`, d8 `tierup`) | the same, twice on one compiled regex | same; catches state carried between runs and tier-up bugs |
| span (`[span]`) | `[start, end)` of the first match of an unanchored search in A and R | the backtracking matcher's first match in priority order, or the relation's leftmost-longest span (POSIX engines) |
| capture (`[capture]`) | the whole match plus groups 1–6 | the matcher's capture slots, with per-engine loop and lookbehind rules |
| offset (`[offset]`; `shell-offset`, `perl-offset`, d8 `offset`) | `[start, end)` of a search that starts at a per-case offset in A and R | the matcher's first match from that offset; `^` still means the real start and lookbehind sees the earlier text. Offsets travel in the flags string as `"<flags>@<a>,<r>"` in the host's units (driver mode `ospan`). Enabled where the engine's API has those semantics; Tcl (`-start`), ICU and Racket treat the offset as the string start, Go, Vectorscan, LLVM, Swift Regex, Emacs and RE# have no such API |
| global (`[global] enabled`; `global`, `shell-global`) | the first 4 matches of a global search (`String.prototype.matchAll`) in A and R | the matcher's matches in order, continuing after an empty match one position on (AdvanceStringIndex: a whole surrogate pair under `u`/`v`); JS engines (driver mode `gspan`) |
| sticky (`[offset] sticky`; `shell-sticky`, `perl-sticky`, d8 `sticky`) | the same offsets, but the match must start exactly there | the matcher's match anchored at the offset. Only for hosts with a native anchored search (JS `y`, Perl `\G`, Python `match(s, pos)`, Java `region` + `lookingAt`, PCRE2 `ANCHORED`, PHP `A`, `onig_match`, Ruby and .NET `\G`, RE2 `ANCHOR_START`; driver mode `aspan`): emulating it from the offset search would only repeat the offset check |
| long (`[long]`; `shell-long`, `perl-long`, d8 `long`) | does the pattern fully match a long accept string? its near-miss reject? | the relation semantics evaluated as bit vectors over positions (`src/long.zig`) |
| long span, long capture (`[long]` with `[span]`/`[capture]`; `*-long-span`, `*-long-capture`) | span mode and capture mode on the long pair | the same references as span and capture mode, on subjects of any length; positions on the wire are 4 hex digits (driver modes `lspan`, `lcapture`) |

**Long inputs.** Short subjects never reach the code engines use for long input: SIMD scanning in 16–64-byte
chunks, DFA state caches, JIT backtracking stacks, 8-bit versus 16-bit string paths, and the 255/256 and 64K
position boundaries. The long mode keeps the short pair as the constraint that selects patterns, then derives a
long pair from it. A segment of A that the pattern's loops can repeat (A with the segment twice and three times
is still accepted) is pumped out to a target length (default 64, 256, 1000 or 4096 symbols), one or two segments
at a time. The reject is a near miss: the long accept with one symbol substituted, deleted or inserted at the
start, the middle, the end, or a power-of-two boundary. Both are checked by a bit-vector evaluation of the same
relation semantics: forward and backward position sets per node, lookarounds and assertions as position masks,
loops closed over their frontier. It costs polynomial time, so it stays exact where engines blow up. A guard runs the
backtracking reference matcher with a budget of 50 steps per symbol and drops pairs it can't finish, so
catastrophic backtracking doesn't turn into a stream of timeouts. Cases with nothing to pump, or with no
near-miss reject (patterns that accept almost anything), get no long pair. Triage shrinks long findings by
deleting chunks the accept and reject share, largest first, down to the shortest strings that still fail.

Hosts report positions in their native unit (UTF-16, code points or UTF-8 bytes: `[span] units`); irx
converts them to UTF-16 offsets, so an offset inside a character is itself a finding. A self-check at
startup probes every atom and assertion against the engine to catch model gaps before fuzzing.

Engine families disagree on a few things that only matter for spans and captures; the dialects record them:

* **Empty loop iterations** (`empty_iteration`): ES rejects an iteration that matched empty and tries the
  next alternative; Perl, PCRE, Python, Java, .NET, Ruby, ICU, Swift, Racket and Emacs accept it and leave the
  loop; RE2, Go, Rust and .NET NonBacktracking have their own rule (`unmodeled`: such patterns are skipped).
* **Captures in loops** (`[capture] loop`): cleared each iteration (`reset`: JS), kept until overwritten
  (`keep`: PCRE family, automata), or not modelled (`unmodeled`: Perl 5.38+). Survey and design:
  [`docs/phase2-captures.md`](docs/phase2-captures.md).
* **Match selection** (`span_semantics`): first in priority order for backtracking engines, leftmost-longest
  for LLVM, Tcl and RE#.

Every semantic difference the dialects record (classes, case folding, anchors, loops, lookbehind rules,
backreferences, offsets, syntax spellings) is collected in [`docs/semantic-quirks.md`](docs/semantic-quirks.md).

## Configuration

A campaign's configuration is [`weights.toml`](weights.toml) followed by the target's `target.toml`
(later keys win). Defaults live in `src/config.zig`.

| Section | Controls | Defaults in `weights.toml` |
|---|---|---|
| `[weights]` | how often each construct is generated | concat 4, alt 1.5, atoms 0.7–1, `(?:)` 0.2, `\p{…}` 0.7, quantifiers 0.08–0.25 (lazy ×0.5), lookarounds 0.4, groups 0.03–0.05, inline flag groups 0.05 |
| `[sizes]` | pattern size (tree nodes) | uniform over 4–24 |
| `[strings]` | subjects A and R | 0–8 code points (empty subjects included), at most 31 decoded symbols; R = A after 1–5 edits; 26-character pool, with `pool_rotation` 0.4 of tables drawing from an alternate pool |
| `[flags]` | flag sets, one per table | 24 sets over `i m s u v` (JS `u`/`v`; other dialects ignore or map them) |
| `[grammar]` | grammar shape | max size 24, counted repeats up to 3 plus big bounds `[16, 100, 254]` (`{0,N}`, `{1,N}`, `{N,}`, `{N}`, weight ×4, only over a single character atom and never inside another quantifier), classes of up to 2 members |
| `[limits]` | table and memory budgets, stored findings | 1 GiB per table, 4 GiB host, 100k samples per table, 20 stored findings per signature group |
| `[harness]` | batches, deadlines, journals | 512 cases per batch, 2 s + 2 s per 512 cases, journals deleted after the run (`keep_journals`) |
| `[target]` (target.toml) | how to launch the engine | `kind` (`d8`, `perl`, `shell`), `command`, `dialect`, `selfcheck`; `env` (variables for irx and the engine, e.g. `IRX_PCRE2_JIT=1`), `modes` / `optional_modes` (d8: `linear`, `noopt`, `nopeephole`, `fallback0`) |
| `[span]`, `[capture]` (target.toml) | range checks | `enabled`, `units`; `loop`, `lookbehind` |
| `[offset]` (target.toml) | start-offset checks | `enabled` (offset mode), `sticky` (anchored at the offset; only for hosts with a native anchored search) |
| `[long]` | long-input modes (off unless enabled) | `enabled`, `only` (no other modes), `span`/`capture` (long spans and captures where the target supports them; default true), `fraction` 0.25 of cases, `lengths` [64, 256, 1000, 4096] (at most 16000), `guard_factor` 50, `deadline_ms_per_kb` 20, `deadline_ms_per_case` 10, `max_request_bytes` 8 MiB |

Three constructs need engine-specific care:

* **Big repeat counts** stay safe for backtracking engines because they only apply to a single character atom that
  can't match empty on A or R, and nothing quantifies them again; the relation model computes `{254}` as cheaply as
  `{3}`.
* **Unicode properties** `\p{X}` / `\P{X}` over 16 general categories (L, Lu, Ll, N, Nd, P, Pc, Pd, Po, S, So, Z, Zs,
  Zl, C, Cc). Case-insensitive matching differs by engine (`prop_case`): ES applies case equivalence and complements
  `\P` before folding; Java, ICU, Onigmo, Rust, RE2 and Go invert `\P` after folding; Perl and PCRE treat Lu/Ll as any
  cased letter; Oniguruma, Vectorscan and nim ignore `/i`; .NET checks the character's simple upper and lower forms and
  its case-folding equivalents. The self-check confirms each rule at startup. JS needs `u` or `v`; Python, Tcl,
  Emacs and LLVM have no properties.
* **Inline flag groups** `(?i:…)`, `(?-s:…)`, `(?m:…)` toggle one flag for a subtree; each table picks the flag (`i`,
  `s` or `m`, as the dialect supports; Ruby spells dotall `m` and has no scoped multiline). The table keeps a second
  atom inventory under the toggled flags, separated by a context bit in the pair key, so only a flag group can join
  the two; the model evaluates each node under its effective flags.
* **Set operands** in `v` mode include `\p{L}`, `\p{Lu}` and `\p{Ll}` (`[\p{L}--\p{Lu}]`, `[\p{Ll}&&[a-c]]`).
* **Mutation mode** (`[grammar] mutate_rate`, default 0.15): constructs the relation model cannot express are spliced
  into a sampled tree, and the case's expected answers come from the backtracking reference matcher instead. A random
  subtree gets an atomic group `(?>…)`, a greedy loop becomes possessive (`x*+` where the dialect spells it, else
  `(?>x*)`), or an atom becomes a backreference `(?:\N)` to an earlier capture group outside loops and lookarounds
  (so engines' loop-capture rules do not matter). A reference to a group that has not matched is empty in ECMAScript
  and fails elsewhere (`backref_unset_matches_empty`). Dialect knobs `atomic_groups`, `possessive`, `backrefs` say
  which engines get which; long mode skips mutated cases.
* **Extended mode**: a quarter of patterns in dialects with scoped `(?x:…)` (Perl family, Java, .NET, Python, Ruby,
  Oniguruma, Rust, ICU, Swift) are printed inside `(?x:…)` with spaces and `# comments` between items, and space and
  `#` literals escaped (hosts that rewrite `\x{H}` use each engine's own escape so it survives `x`).
* **`\h \H \v \V`** in the Perl family and Java (PCRE2's and Java's `\h` include U+180E; Perl's does not).
* **`\q{…}`** with one-character strings as `v`-mode set operands, and classes of multi-character strings
  (`[\q{ab|a}]`, `[\q{aab|b}]`): the model tries the alternatives longest first with backtracking, as ES
  does. The `irregexp` dialect (V8, SpiderMonkey) keeps `\q` out of `i` because of IRX-V8-5.
* **`\X`** (Perl family, Java, ICU, Ruby, Oniguruma, Python `regex`): one extended grapheme cluster (UAX #29,
  `src/grapheme.zig`) from the current position, matched atomically and kept out of lookbehind. A grapheme pool
  (marks, ZWJ, emoji and modifiers, regional indicators, Hangul jamo, a Prepend mark, Devanagari conjuncts) joins the
  pool rotation. GB9c is a dialect choice (Oniguruma and PCRE2 lack it); Boost (IRX-BOOST-3) and PCRE1 (Unicode 10-era data)
  are left out.
* **Full case folding** (Perl, Ruby, Oniguruma): under `i` a pattern `ß`, `ẞ`, `ﬀ`, `ﬁ` or `İ`, as a literal or a member
  listed in a non-negated class, also matches the subject strings its full fold spells (`ss`, `sS`, `ſs`, …). These
  characters stay out of subjects (`pattern_only`), since a subject `ß` would also match the pattern `ss`, which the
  atom model cannot see. Such atoms are kept out of lookbehind.
* **Shootout 2** (`tools/irx_bench.py`): every host has a `bench` mode (compile once, then timed unanchored
  searches). The tool times 49 engines on one shared workload (ASCII and Unicode pattern sets, four subject sizes),
  splits each engine's speed relative to Rust by set, accept/reject and size, joins feature counts from the dialect
  model (`irx features`) and open ledger bugs, and assigns S–F tiers. Results: [`docs/shootout2/summary.json`](docs/shootout2/summary.json).
* **Cross-engine check** (`tools/irx_diff.py`): irx skips span and capture checks on Rust, Go, RE2 and
  regex-automata for patterns with a loop over an empty-matchable body (their rule is not modelled). These engines
  all document RE2's leftmost-first semantics, so the tool runs the same patterns (ASCII syntax common to all,
  forced nullable loops) through Rust `regex`, regex-lite, regex-automata's PikeVM and backtracker, Go, RE2 and
  re2j in capture mode and groups disagreements by which engines side together. 50,000 cases: the six non-RE2
  engines never disagree; RE2 alone differs in 10 (IRX-RE2-3).
* **Duplicate named groups** (ES2025): in a quarter of ES patterns, for each alternation the first named group on
  its right takes the name of the first on its left (`(?<g1>a)|(?<g1>b)`). A name is shared by at most two groups,
  always in different alternatives; capture numbers do not change, so the model is unchanged. `[grammar]
  duplicate_names = false` turns it off (Hermes rejects repeated names).

The default character pool is chosen for the places engines get wrong: `a b k s A K S 0 _`, space, `\n`,
`\r`, `-`, `.`, `ſ` (U+017F), `K` (U+212A Kelvin), U+2028, `😀` (U+1F600, an astral character),
`à é ß İ ı σ ς Σ`. Semantics are full Unicode (Unicode 17.0 case folding, per-dialect `\w \d \s \b`,
line terminators). **Pool rotation** (`[strings] pool_rotation`) draws a share of tables from one of three alternate
pools instead, used for both the subjects and the class members:

* case folds: `ſ K ß ẞ ﬀ ﬁ İ ı Ǆ ǅ ǆ ς σ Σ µ μ Å å` (multi-character folds, title case, compatibility signs);
* Cyrillic and Greek: `а А ё Ё ѐ ӏ Ӏ ω Ω Ω ϑ θ ϴ ϕ φ Ϝ ϝ ΐ ΐ` (symbol variants, characters with equal full folds);
* spaces, digits and invisibles: VT, FF, NEL, NBSP, U+1680, U+180E, U+2007, U+202F, U+3000, LS, PS, U+FEFF, ZWSP,
  ZWJ, a combining acute, `٣ 𝟎 ⅷ ①` (`\s`, `\d`, `\w` and `\b` edge cases).

Explicit ranges include non-ASCII endpoints (`[à-ÿ]`, `[À-Þ]`, `[α-ω]`, `[Α-Ω]`, `[а-я]`, `[k-ſ]`) whose case
partners fall outside the range.

## Determinism and storage

A run is a pure function of its seed and configuration (with `[adaptive]` off, the default). Tables are built
in sequence from `(seed, seq, attempt)`, and case `k` of a table comes from its own random stream
`(seed, seq, attempt, k)` (the long pair too), so the same case is generated whichever lane runs it and however
many lanes there are. Lanes take consecutive chunks of the current table. `irx replay` rebuilds the table,
verifies its digest and re-derives the case from `(seed, table, index)` (records say `derive=table`; older ones
used a per-lane index and still replay).

Because any case can be regenerated, stored findings are a sample, not the record. At most
`max_findings_per_group` (`[limits]`, default 20) are stored per signature group (kind, mode, and which constructs
occur), and at most `max_findings_per_mode` (2000) per kind and mode; the rest are only counted in
`groups/counts.txt`, and the run summary reports `over_group_cap`.
Per-process request journals are deleted when the run ends unless `[harness] keep_journals = true`. A batch
failure (crash, timeout) still keeps its exact request in `batch.req`; what is lost is the replay of a
process's earlier batches for sequence-dependent failures.

## The `irx` binary

```sh
irx [fuzz] (--d8 PATH | --shell CMD | --perl CMD) --dialect NAME --config FILE --out DIR
           [--jobs N] [--seed N] [--duration SECONDS] [--max-cases N] [--no-selfcheck]
           [--modes ...] [--optional-modes ...] [--sm PATH] [--jsc PATH]     # d8 only
irx selfcheck ...               # atom and assertion self-check only
irx replay FINDING_DIR ...      # model recheck, table digest, re-derive, rerun
irx triage ... --out DIR        # resume triage of untriaged findings
irx gate --d8 PATH --out DIR    # performance gate (d8)
irx sample [--config F]         # distribution diagnostics, no engine
```

`--shell CMD` speaks the line protocol to any host (`{driver}` and `{mode}` are substituted; JS shells run
`driver.js`, Perl runs `driver.pl`). `--jobs 0` uses the physical core count; with M active modes there are
floor(jobs / M) lanes. A once-per-second stats line shows throughput, per-stage times, memory, findings and
per-mode executed/skipped/mismatch/restart counts.

## Layout

* `src/` — the fuzzer (module map below). `src/dialects/*.zig` — one exact model per engine family (es, perl,
  swift, rust/fancy, re2/go, python, java, ruby/oniguruma, dotnet, icu, resharp, nim, racket, tcl, emacs,
  vectorscan, llvm): character predicates, case rules, anchors, escape syntax, grammar restrictions, and the
  span/capture semantics above.
* `targets/<name>/` — `target.toml` (launch command, dialect, overlays) and `README.md` (that engine's
  campaign results and triage notes).
* `hosts/` — protocol hosts in C, C++, Go, Rust, Java, C#, Swift, Nim, Racket, Emacs Lisp, Python, Ruby, PHP
  and Tcl; `hosts/build.sh` builds the native ones. `driver.js` serves every JS shell; `tools/bridge.py` serves
  shells without stdin (one process per batch; a batch that times out is split and a hanging case is reported
  as unsupported). `driver.pl` serves Perl.
* `tools/` — `irx_target.py` (campaigns), `probe.py` (ask a host ad-hoc questions), `summarize.py`,
  `mismatches.py`, `gen_emacs_tables.py`.
* `docs/` — design notes ([phase 2 captures](docs/phase2-captures.md)) and reproducers that need a whole batch.
* Empty atoms print as `(?:)`, as nothing where the syntax allows (`(?:|a)`, `a|`, `(?=)`), or as `()`, chosen
  per case by a recorded `spell` seed (replay and shrinking reuse it); parser bugs often depend on the spelling.

## Output layout

```
OUT/manifest.json       seeds, build identity, engine path/hash/version, driver hash, Unicode manifest,
                        resolved config, per-flag-set atom and quantifier inventories, modes, probes
OUT/config.toml         copy of the config used (replay/triage read it automatically)
OUT/tables.log          every table: identity, A/R/flags, digest, per-level build stats and truncation
OUT/selfcheck/          report.txt and mismatches.tsv
OUT/findings/NNNNNN/    case.irx (machine-readable), case.json, repro.js, manifest.json (span/capture details),
                        triage.json, repro.min.js + minimized.irx (semantic findings),
                        batch.req/stderr.txt/isolated.req/sequence.jsonl (crash/timeout findings)
OUT/groups/KIND__MODE__CONSTRUCTS.txt   navigation index
OUT/slow/index.txt      timeouts, kept apart from semantic findings
OUT/journals/           per-process request journals (deleted only if unreferenced)
OUT/summary.json        end-of-run totals
```

Finding kinds: `wrong_result`, `wrong_span`, `wrong_capture`, `tier_mismatch`, `syntax_error`, `exception`,
`crash`, `timeout`, `protocol`, `selfcheck_mismatch`, `sanity_disagreement`.

## Module map

| File | Role |
| --- | --- |
| `src/rel.zig` | `Rel(N)` for N ∈ {8, 16}: product, closure (Warshall), bounded powers by squaring, lookaround diagonals |
| `src/ucd.zig`, `src/ucd/` | Vendored Unicode 17.0.0 (CaseFolding, UnicodeData, SpecialCasing) with SHA-256 manifest verified at startup |
| `src/alphabet.zig` | Flags, UTF-16 → symbol decoding per mode, the character pool, dialect-dispatched predicates |
| `src/dialect.zig`, `src/dialects/` | Dialect interface and one model per engine family; grammar restrictions mirrored for the shrinker |
| `src/atoms.zig` | Atom specs and their semantics (ES2024 CharacterSetMatcher, v-mode set operations, case folding), assertion masks |
| `src/ast.zig` | Trees, relation evaluation, the reference backtracking matcher (search, captures), serialization |
| `src/table.zig` | Grammar inventory, pair interning with subtree flags, production set, budgeted levels, counts, digest |
| `src/budget.zig` | Hard byte accounting on every allocation |
| `src/sample.zig` | Alias-table sampling and the dialect-aware printer (empty-atom spellings, group numbering) |
| `src/span.zig`, `src/capture.zig` | Span and capture references, host unit conversion, comparison, finding details |
| `src/long.zig` | Long-input mode: bit-vector reference for subjects of any length, pumping generator, backtracking guard |
| `src/harness.zig` | Process spawning, nonblocking transport, deadlines, journals, modes and probes |
| `src/lane.zig` | Per-lane sample → fan-out → compare → persist loop |
| `src/run.zig` | Table publication, background builder, string drawing, adaptive weights, triage queue |
| `src/shrink.zig` | Triage: fresh-process reproduction, tree/string/flag shrinking, batch bisection, journal replay |
| `src/selfcheck.zig` | Startup atom and assertion self-check |
| `src/finding.zig` | Cases, failure predicates, persistence, dedup |
| `src/main.zig` | CLI, config, probing, manifests, stats line, subcommands |
| `driver.js`, `driver.pl` | JS and Perl protocol drivers (embedded; hashes recorded in the manifest) |

## Validation status

* **Model vs. backtracking matcher**: >3,000 random trees across 11 flag sets agree (`ast.zig` test).
* **Long-input reference**: the bit-vector evaluation agrees with the relation model on 6,600 random trees across
  11 flag sets, forward and backward; every generated long pair is accept/reject under it (`long.zig` tests).
  Long-only runs on PCRE2, RE2, Bun and .NET NonBacktracking (about 45k long pairs) show no mismatches, and a
  hand-built IRX-DOTNET-6 case with a 502-character accept string minimizes to its known 4-character repro.
  Every host answers the wide-format probe (a match at position 300); a 45-second long, long-span and
  long-capture sweep over all 32 targets found only known bugs plus IRX-JAVA-6 and IRX-XS-11.
* **Self-check**: every dialect reaches 0 self-check mismatches against its engine, apart from known engine bugs
  (IRX-SWIFT-1, IRX-JAVA-1, RACKET-1, the XS `v`-mode bugs). A one-line injected model bug yields ~1,000
  mismatches, so the check has teeth.
* **Span and capture modes**: deliberately wrong host units produce `wrong_span` findings that minimize to one
  atom; sweeps over all targets leave only known engine bugs, resource limits, or unminimized findings.
* **Counts**: exhaustive enumeration of small grammars matches table counts to <1e-5 relative error; sampling
  frequencies match exact tree probabilities within 5.5σ over 60k draws.
* **Transport**: tests for partial writes, malformed responses, stalled children, stderr flooding, signal death,
  EOF and malformed handshakes; hosts are checked with a known-answer probe at startup.
* **Budgets**: deterministic truncation under tiny caps, resource rejection with zero leaked bytes, finite retries.

## Limitations and measured decisions

* **Default weights** favour concat and alternation: with all-ones weights about half of all nodes were nested
  quantifiers and nearly every batch timed out on catastrophic backtracking.
* **Hanging engines**: Boa (IRX-BOA-8), XS (IRX-XS-7) and ICU (IRX-ICU-1) loop forever on some patterns. Bridged
  shells split a timed-out batch and report the hanging case as unsupported; the Swift host abandons an ICU
  match after 50 ms. Those targets use small batches and long deadlines, and still run slower than the rest.
* **Skipped cases** (counted, never treated as agreement): lone surrogates on UTF-8 hosts; patterns whose
  span or capture semantics an engine doesn't share with the model (see *What each case checks*).
* **Tree shrinking** uses structural AST reductions with direct relation evaluation (the spec's documented
  fallback), recorded in each `triage.json`.
* **One batch in flight per lane**; parallel table construction is not implemented.
* **V8 specifics** (from the d8 design): tier transitions are reported as unverified (`--trace-regexp-tier-up` is
  read-only in the Homebrew build); the `linear` mode skips `m` and marks u/v and lookaround cases as
  unsupported; SpiderMonkey via jsvu shares irregexp, so its agreement is not independent; d8 is the Homebrew
  release build, not `dcheck_always_on`.
* **Finding artifacts** are written atomically (temp + rename) without fsync.
* **Long modes**: most hosts have no per-case time limit, so a pattern the guard passes but an engine backtracks
  on for seconds still costs its whole batch; the deadline grows with request size to absorb ordinary slowness.
  .NET (250 ms per match) and fancy-regex (its backtrack limit) report such cases as unsupported. About half of the
  cases get a long pair; the rest have nothing to pump or no near-miss reject. Engines that compile every
  pattern from scratch (Vectorscan, RE#) and the slow shells (engine262, Boa, XS, Hermes) run few long cases.

<!-- BEGIN shared bug ledger (identical on every branch) -->
## Bug ledger

Two sources: bugs found by this inverted-pair fuzzer (irx), and bugs found earlier by differential fuzzing in
the sibling repo [`../regex_comparison`](../regex_comparison/bugs/BUGS.md) (imported 2026-10-09; IDs link to
that repo's write-ups, which hold full repros and upstream-search notes). Report status and links are
recorded in the tables below. Older V8 builds (Node 25.8 = V8 14.1, Deno 2.9.7 = V8 15.0) are fuzzed as the
`node`/`deno` targets but excluded from this ledger: d8 15.5 is the up-to-date V8 target.

### Found by irx

| ID | Engine | Status / report | Repro / behavior | Notes |
|---|---|---|---|---|
| IRX-V8-1 | V8 | Related · [#571450188](https://issues.chromium.org/issues/571450188) | wrong result: `/(?:.*?B^\|a)/s.test("a")` → `false` → expected `true` | Tested: V8 15.5.35.20 (d8). quick-check family; fixed by `--no-regexp-quick-check` and `--no-regexp-optimization`. Same family as [V8-3](../regex_comparison/bugs/BUGS.md#v8-3); not separately reported |
| IRX-V8-2 | V8 | Open · [#572331418](https://issues.chromium.org/issues/572331418) | wrong result: `/^(?:.*?a^)*$/s.test("")` → `false` → expected `true` | Tested: V8 15.5.35.20 (d8). Confirmed from the report's repro; fixed by `--no-regexp-quick-check`, not by `--no-regexp-optimization` |
| IRX-V8-3 | V8 | Open · [#572331419](https://issues.chromium.org/issues/572331419) | wrong result: `/(?<![\s\S])(?:(?:^)*)(?![\s\S])/mu.test("😀")` → `true` → expected `false` | Tested: V8 15.5.35.20 (d8). Confirmed from the report's repro; match starts inside a surrogate pair; related to [V8-1](../regex_comparison/bugs/BUGS.md#v8-1) / [V8-2](../regex_comparison/bugs/BUGS.md#v8-2) |
| IRX-V8-4 | V8 | Related · [#572331419](https://issues.chromium.org/issues/572331419) | wrong span (inside a surrogate pair): `/(?!.)\|a^/u.exec("😀").index` → `1`; also `/\n\|(?!^)/u` → expected `2` (`/(?!.)/u` alone gives `2`) | Tested: V8 15.5.35.20 (d8). the V8-2 surrogate-pair problem is still reachable in current V8 when the zero-width branch sits in an alternation; Node 25 (V8 14.1) also fails the single-branch form. Found by span mode; not separately reported |
| IRX-V8-5 | V8 | Open · not filed | wrong result: `/^[\q{k}]$/vi.test("K")` → `false`; also `/^[\q{\u{17F}}]$/vi.test("\u017F")` → `false` while it matches `"s"`, and `/^[[a-z]--\q{a}]$/vi.test("A")` → `true` (`[[a-z]--[a]]` gives `false`) → expected `true`, `true`, `false` (QuickJS, JavaScriptCore; ES MaybeSimpleCaseFolding applies to class strings like any other operand) | Tested: V8 15.7.77 (d8), Node (V8), SpiderMonkey (jsvu; Irregexp). Under `vi` a `\q{…}` string is folded but the subject character is not, so strings match only subjects already in folded form. Found by the self-check after `\q{}` strings were added; the `irregexp` dialect keeps `\q` out of `i` for the V8 and SpiderMonkey targets |
| IRX-PERL-1 | Perl | Resolved in blead 5b2f72d · [#24943](https://github.com/Perl/perl5/issues/24943) | wrong result: `"0a" =~ /\A(?=a*)[0-9]a\z/` → false → expected true | Tested: Perl 5.34.1, 5.44.0, blead 5.45.4. Rechecked on freshly built upstream blead `23257acb8515` (2026-10-10): still reproduces. Optimizer builds an empty start class (`re 'debug'`: `synthetic stclass "ANYOF[]"`); also in loops: `"b" =~ /\A(?:(?=a*).)+\z/`; simplest form (unanchored, found by long span mode): `"x" =~ /(?=a?)./` → no match, and `"xa" =~ /(?=a?)./` matches at 1 (5.44.0 and blead 5.45.4); `^(?=a?).`, `(?=a\|).` and `(?=a?)x` are correct **Rechecked 2026-10-15: resolved in Perl blead 5.45.4 (`5b2f72d`); still fails in 5.44.0.** |
| IRX-PERL-2 | Perl | Open · [#24944](https://github.com/Perl/perl5/issues/24944) | wrong result: `"a" =~ /\A^\ba*\z/m` → false → expected true | Tested: Perl 5.34.1, 5.44.0, blead 5.45.4. Rechecked on freshly built upstream blead `23257acb8515` (2026-10-10): still reproduces. Also reduces to `"a" =~ /^\ba*$/m` → false (expected true); needs `/m`, `^`, `\b` and an optional quantifier (`*` or `?`), but not `\A` |
| IRX-PERL-3 | Perl | Resolved in blead 5b2f72d · [#24945](https://github.com/Perl/perl5/issues/24945) | wrong capture: `"aa" =~ /(?:(aa){2})*/` → match `[0,0)` but `$1` = `"aa"` at `[0,2)`; `"aaaaaa" =~ /(?:(aa){2,2})+/` → match `[0,4)`, `$1` at `[4,6)` (outside the match) → expected `$1` undef; `$1` at `[2,4)` | Tested: Perl 5.44.0 (5.34.1 is correct). a capture set during a loop iteration that later fails is not restored; likely from the 5.38 change that resets captures in quantified groups (perl5380delta). Found by capture mode (phase 2) **Rechecked 2026-10-15: resolved in Perl blead 5.45.4 (`5b2f72d`); still fails in 5.44.0.** |
| IRX-PERL-4 | Perl | Resolved in blead 5b2f72d · [#24946](https://github.com/Perl/perl5/issues/24946) | wrong capture: `"a\na" =~ /a*?(?!a()).a/s` → match `[0,3)` with `$1` at `[1,1)`; expected `$1` undef (Python, V8) | Tested: Perl 5.34.1 and 5.44.0. A capture made inside a negative lookahead whose body matched (so the lookahead failed) survives after backtracking into a path where the lookahead succeeds; `"ab" =~ /(?!a())./` alone is fine. Found by capture mode **Rechecked 2026-10-15: resolved in Perl blead 5.45.4 (`5b2f72d`); still fails in 5.44.0.** |
| IRX-PERL-5 | Perl | Resolved · related to [#24926](https://github.com/Perl/perl5/issues/24926) | wrong span: `"aa" =~ /(?:b??ı|)a+/` → match `[0,1)`; also `(?:b??ı)?a+`, `(?:b??\x{100}|)a+` → expected `[0,2)` (Python, PCRE2; the greedy `a+` takes both) | Tested: Perl 5.44.0 and blead 5.45.4, with or without `/u`. A lazy optional item followed by a character above U+00FF (`ı`, `Ā`; `é`, `ÿ` are fine) in an optional group or alternative cuts the following greedy loop to one iteration; `(?:b?ı|)a+` (greedy) is correct. Found by the 30-minute campaign's capture mode (`(?:a{0,1}?\x{131}|(?:))a+`). Rebuilt blead `06de9ae` (2026-10-11): full greedy matches after fix `b27da40` for #24926; no separate report needed |
| IRX-PERL-6 | Perl | Open · not filed | wrong result: `"\x{1FD3}" =~ /[\x{390}\x{1FD3}]/` → false; `"\x{390}"` → false → expected true for both (each is a member of the class; no `/i`) | Tested: Perl 5.44.0, blead 5.45.4. U+0390 and U+1FD3 have the same full case fold (ΐ → ΐ, three code points); a class holding exactly these two matches neither, while `[\x{1FD3}]` and `[\x{1FD3}a]` match. Found by pool rotation (Cyrillic/Greek pool). |
| IRX-PERL-7 | Perl | Open · not filed | wrong result: `"ß" =~ /^[s\x{FB01}]$/i` → true; also `"ẞ"`, and `[s\x{FB00}]`, `[S\x{FB01}]`, `[\x{17F}\x{FB01}]` → expected false (`/^[s]$/i` is false; ß folds to `ss`, two characters) | Tested: Perl 5.44.0, blead 5.45.4. Adding a ligature with a multi-character fold (ﬁ, ﬀ) to a class makes `s` match ß, which consumes half of its fold `ss` as one class match. Found by pool rotation (case-fold pool). |
| IRX-PERL-8 | Perl | Open · not filed | wrong result (state carried between matches): `perl -le '"" =~ /x?y?/; print "a" =~ /^a(?<!(?>a))/ ? "match" : "no"'` → `match`; without the earlier match → `no` → expected `no` (the `a` before the end is matched by `(?>a)`) | Tested: Perl 5.44.0, blead 5.45.4. A successful earlier match of `/x?y?/` (two optional items; also `/^(x)?a-?b$/` and the ones `Encode::Alias` runs when JSON::PP loads) makes a later negative lookbehind holding an atomic group succeed where it fails; `(?<!(?:a))` and `(?<!a)` are unaffected. Found by mutation mode (atomic groups) through the Perl driver, which loads JSON::PP. The same earlier match also makes a positive lookbehind holding an atomic group fail: `"a" =~ /(?<=(?>(?:)))a/` → no match (a fresh process matches). Rechecked on upstream blead `90cd16d` (2026-10-12): both still reproduce; the blead campaign traces about 8,900 findings to this (atomic groups and possessive quantifiers inside lookarounds). |
| IRX-XS-1 | XS | Open · [#1751](https://github.com/Moddable-OpenSource/moddable/issues/1751) | rejects valid pattern: `new RegExp("[]", "v")`, `new RegExp("[^]", "v")` → SyntaxError → expected accepted (ES2024) | Tested: XS (jsvu, Moddable). empty `ClassContents` is legal in UnicodeSets mode |
| IRX-BOOST-1 | Boost.Regex | Open · not filed | wrong result: `boost::regex_match("", boost::regex("(?:$)+"))` (Perl syntax, `^`/`$` at lines) → false; also `a(?:$)+` and `a(?:$){1,1}` on `"a"` → expected true (`(?:$)` alone matches `""`) | Tested: Boost 1.92 (Homebrew). Repeating an assertion that holds at the current position fails the match. The `boost` dialect stops generating quantified assertions. Found by the new `boost-regex` target's sweep. |
| IRX-BOOST-2 | Boost.Regex | Open · not filed | wrong span (not leftmost): `boost::regex_search("aaaa", m, boost::regex("a{0,2}?a\\b"))` → `[2,4)`; `a{0,3}?a$` on `"aaaaa"` → `[3,5)` → expected `[1,4)`; `[1,5)` (Perl) | Tested: Boost 1.92 (Homebrew). A lazy bounded repeat `{0,n}?` (n ≥ 2) at the start of the pattern makes the search skip a valid starting position; `a{0,1}?a$` and the greedy `a{0,2}a\b` are correct. Found by span mode on the `boost-regex` target. |
| IRX-BOOST-3 | Boost.Regex | Open · not filed | wrong result: `boost::regex_match(" a", boost::regex("a?\\Xa"))` → false; also `a*\Xa` on `" a"`, `b*\Xa` on `"ba"`, `()?\Xa` on `"_a"` → expected true (`\X` matches the space, then `a`; `(?:)\Xa` and `\Xa` match) | Tested: Boost 1.92 (Homebrew), narrow and wide APIs. An optional or repeated element before `\X` makes the whole match fail, even when the element matches empty. Found by the round-10 campaign on `boost-regex` and `boost-asan`; the `boost` dialect no longer generates `\X` |
| IRX-BOOST-4 | Boost.Regex | Open · not filed | wrong captures: `boost::regex_search("a", m, boost::regex("(?>(a))?a"))` → group 1 `[0,1)`; also `(?>a())?a` → group 1 `[1,1)`, `(a)*+a|a` on `"aa"` → group 1 `[1,2)` (the match takes the second alternative); lookarounds too: `(?:(?=(?<g1>))[^ab])?` on `"a"` and `(?!(?<g1>))|\n` on `"\n"` → group 1 `[0,0)` → expected unset (Perl, PCRE2: a group inside an atomic group or possessive loop that backtracking abandons is reset; `(?:(a))?a` is correct in Boost) | Tested: Boost 1.92 (Homebrew). Found by the round-10 campaign (mutation mode, capture checks) on `boost-asan`; the `boost` dialect no longer generates atomic groups or possessive quantifiers |
| IRX-BOOST-5 | Boost.Regex | Open · not filed | wrong result: `boost::regex_match("0A", boost::regex("(?i:0+)?A"))` → false; also `(?i:0{1,2})?A`, `(?i:0+?)?A`, `(?i:[0-9]+)*[A_]` on `"0A"`, `(?-i:a+)?[k-s]` on `"aK"` under `(?i)` → expected true (Perl, PCRE2, Python) | Tested: Boost 1.92 (Homebrew). After an optional (or starred) group with an inline case flag whose body is a loop, the next item is matched under the wrong case mode (in either direction): `(?i:0+)?a` on `"0a"` is true, but `(?i:0+)?A` fails on both `"0A"` and `"0a"`; `(?i:0+)A`, `(?i:0)?A`, `(?-i:0+)?A` and `(?s:0+)?A` are correct. Found by the r2h campaign (2 hours) on `boost-asan` |
| IRX-BOA-1 | Boa | Open · [#5576](https://github.com/boa-dev/boa/issues/5576) | rejects valid input (JSON): `JSON.parse('"\\ud83d"')` → SyntaxError → expected 1-unit string | Tested: Boa (`boa_cli`, cargo). lone-surrogate escapes are valid JSON; not a regex bug, found while wiring the harness |
| IRX-BOA-2 | Boa | Open · [#5569](https://github.com/boa-dev/boa/issues/5569) | wrong result: `/^[\uD83D\uDE00]$/.test("\ud83d")` → `false` → expected `true` | Tested: Boa (`boa_cli`, cargo). without `u`, an escaped high surrogate followed by another escape in a class is mishandled (also `[\uD83D\u03A3]`); `new RegExp("[^\\uD83D\\u03C2]").test("ς")` → `true` while the literal `/[^\uD83D\u03C2]/` is correct (found by long mode) |
| IRX-BOA-3 | Boa | Open · [#5570](https://github.com/boa-dev/boa/issues/5570) | wrong result: `/^s$/i.test("ſ")` → `true` → expected `false` | Tested: Boa (`boa_cli`, cargo). non-`u` `i` uses Unicode simple folding instead of `toUpperCase` canonicalization; `\w`/`i` also matches ſ and K |
| IRX-BOA-4 | Boa | Open · [#5571](https://github.com/boa-dev/boa/issues/5571) | wrong result: `/^(?:\D\b)$/iv.test("\u212a")` → `false` → expected `true` | Tested: Boa (`boa_cli`, cargo). `\b` ignores the extra `iu`/`iv` word characters (ſ, K) |
| IRX-BOA-5 | Boa | Open · [#5572](https://github.com/boa-dev/boa/issues/5572) | wrong result: `/^(?:(?:\s(?:(?:){0,1}\|a))+)+$/.test("\u2028a")` → `false` → expected `true` | Tested: Boa (`boa_cli`, cargo). an empty group quantified `{0,1}` as an alternative breaks nested loops; `(?:\|a)` is fine |
| IRX-BOA-6 | Boa | Open · [#5573](https://github.com/boa-dev/boa/issues/5573) | wrong result: `/^[s[^a]]$/iv.test("a")` → `true` → expected `false` | Tested: Boa (`boa_cli`, cargo). nested complements in `v` classes are not case-folded under `i` |
| IRX-BOA-7 | Boa | Open · [#5574](https://github.com/boa-dev/boa/issues/5574) | wrong result: `/(?:(?:a+)+){2}/.test("aa")` → `false` → expected `true` | Tested: Boa (`boa_cli`, cargo). a counted repeat of a group whose body is a quantified quantifier; `(?:(?:a+){1}){2}` and `(?:(?:a{2,3}){2}){2}` on `"a"×8` fail too, `(?:a+){2}` and `(?:(?:a+)*){2}` are fine; also Hermes (IRX-HERMES-3) and XS (IRX-XS-4); capture mode: `/(?:((?:a+){1,1})|(?:)){2}a/.exec("aa")` leaves group 1 = `"a"` from an abandoned iteration (V8: undefined) |
| IRX-BOA-8 | Boa | Open · [#5575](https://github.com/boa-dev/boa/issues/5575) | hang: `/(?:(?:a\|)*)*b/.test("a")` never returns → expected `false` | Tested: Boa (`boa_cli`, cargo). a nullable alternative inside two nested stars loops forever once the match fails; also `(?:(?:a\|(?:)?)*)*b`. Accounts for most Boa batch timeouts |
| IRX-QJS-1 | QuickJS | Resolved · related to [#520](https://github.com/bellard/quickjs/issues/520) | rejects valid pattern: `new RegExp("-", "v")`, `new RegExp("a-b", "v")` → SyntaxError → expected accepted | Reproduces in Homebrew QuickJS 2026-06-04. Already reported as upstream #520 and marked fixed. Built current `bellard/quickjs` source at `9d01a96` (2026-10-10): both patterns compile and match; no new report needed |
| IRX-QJS-2 | QuickJS | Open · not filed | rejects valid pattern: `new RegExp("[\\q{a\\-}]", "v")`, also `[\q{\&}]` → SyntaxError → expected accepted (escaped ClassSetReservedPunctuator inside a class string); conversely `[\q{a-}]` (unescaped `-`, a ClassSetSyntaxCharacter) is accepted → expected SyntaxError (V8) | Tested: QuickJS upstream `ea3deb1` (2026-10, built today) and Homebrew 2026-06-04. GraalJS also accepts `[\q{a-}]`. Found by the self-check after `\q{}` strings were added |
| IRX-NIM-1 | nim-regex | Open · not filed | wrong result: `match("ı", re2"(?i)[à-ÿ]")` → true; also `"Ā"`, `"ŷ"`, `"ß"`, `"İ"` → expected false (none is case-equivalent to a member of à–ÿ) | Tested: nim-regex 0.26. Case-insensitive ranges also accept every code point between the endpoints' upper forms (À..Ÿ, U+00C0..U+0178) and between their lower forms, instead of the case partners of the members. Found by the non-ASCII ranges and pool rotation. |
| IRX-NIM-2 | nim-regex | Open · not filed | wrong result: `"ba".match(re2"(?x:b(?=a) a)")` → false; also `(?x:b (?!c) a)`, `(?x:b(?<=b) a)` → expected true (in extended mode the space is ignored; `(?x:b (?=a)a)` and `b(?=a)a` match) | Tested: nim-regex 0.26.3. Whitespace after a lookaround in `(?x:…)` makes the match fail. Found by the round-10 campaign (extended mode) on `nim-regex` |
| IRX-PCRE2-1 | PCRE2 | Related · [#974](https://github.com/PCRE2Project/pcre2/issues/974) | wrong result: `/(?<!(?:\|a)$)a/` on `"a"` → no match; `/(?<=a?\b)a/`, `/(?<!a?\B)a/` on `"a"` → no match → expected match | Tested: PCRE2 10.49 **JIT** (also PHP 8.5 `preg_*`, JIT on by default). interpreter correct; a lookbehind (positive or negative) whose body is a variable-length part (`a?`, `a??`, `(?:\|a)`) next to `$`, `\z`, `\b` or `\B`. `(?<=a?^)a`, `(?<=a?)a` and `(?<!(?:\|a)x)a` are fine. Same JIT miss as #974's `(?<=a?(?=b))b` (a lookahead in place of the assertion); added there as a comment, not separately reported |
| IRX-PCRE2-2 | PCRE2 | Open · not filed | wrong span: `pcre2_match("(?:^\\B\|..){0,2}\\S", " .-x0")` → `[0,3)` → expected `[0,5)` (Perl, V8) | Tested: PCRE2 10.49 (interpreter and JIT; also PHP 8.5). after the first iteration matched empty (`^\B` at 0) and was backtracked into `..`, the second iteration is never tried before `\S`; with a literal (`…{0,2}0`) the span is right. Found by span mode; also `(?:^\|.){0,3}\\B` on `"aa-"` → `[0,1)` (Perl `[0,3)`) |
| IRX-PCRE2-3 | PCRE2 | Open · not filed | wrong result (no match): `/(?:é\| )\\D{2}/u` on `" aa"` → no match under `pcre2_jit_compile`; also `\\S{2,}`, `\\w{2,}`, first branch `ı` or `σ` → expected `[0,3)` (interpreter) | Tested: PCRE2 10.49 **JIT** (also PHP 8.5). an alternation whose first branch is a non-ASCII literal and whose later branch matches, followed by a class escape repeated two or more times; `(?: \|é)`, `[é ]`, `\\D{1,}` and `[^0-9]{2,}` are fine. Found by span mode on PHP |
| IRX-PCRE2-4 | PCRE2 | Open · not filed | wrong result: `/\P{So}+\P{Sm}/utf` on `"ab"` → no match; `/a\P{So}*\D/utf,ucp` on `"aaa"` → no match (`\D` is `\P{Nd}` under UCP); also `\P{L}*\P{N}` on `"--"` → expected a match (Perl; PCRE2 with `no_auto_possess`) | Tested: PCRE2 10.49 (`pcre2test`, interpreter). Auto-possessification treats a loop over one negated general category as possessive when a different negated category follows, although the two sets overlap; `\P{Lu}*\P{Ll}` is fine. Found by the new `\p{…}` atoms (offset-mode sweep). Also in PCRE1 8.45 (`\D*\P{So}` misses `"a"`, interpreter and JIT), so the bug predates PCRE2. |
| IRX-PCRE2-5 | PCRE2 | Open · not filed | wrong result: `pcre2test` `/(?<=(?<!a)a)b/utf` on `aaab\=offset=3` → `0: b`; also `/(?<=(?<!a)a)/utf` (empty match at 3) → expected no match (the `a` before the `b` is itself preceded by `a`) | Tested: PCRE2 10.49 (`pcre2test`, interpreter). With a non-zero start offset in UTF mode, a lookbehind nested in a lookbehind does not see the text before the offset; without `utf`, at offset 0, and under the JIT the result is correct. Found by offset mode on the `pcre2-ascii` target. The same happens to `\b`/`\B` inside a lookbehind: `/(?<=\ba)/utf` on `aa\=offset=2` → `0:` (empty match; no boundary between the `a`s), `/(?<!\b.)/utf` on `ab\=offset=2` → no match (expected `0:`); also through Erlang `re` (OTP 29), found by the r2h campaign on `erlang-re`. |
| IRX-PCRE2-6 | PCRE2 | Open · not filed | wrong result: `pcre2test` `/^\X$/utf` on `\x{600}\x{2764}` (ARABIC NUMBER SIGN, a Prepend character, then HEAVY BLACK HEART) → no match; also any Prepend followed by an Extended_Pictographic character → expected match (UAX #29 GB9b: no break after Prepend; Perl, ICU, Java, Onigmo, Python `regex` agree) | Tested: PCRE2 10.49 and current `master`: the Prepend row of `ucp_gbtable` (`src/pcre2_tables.c`) lists every following class except `ucp_gbExtended_Pictographic`. Found by the self-check after `\X` was added; the `pcre2` dialect follows it (`grapheme_prepend_pict`) |
| IRX-PCRE2-7 | PCRE2 | Open · not filed | wrong result: `pcre2test` `/(?<=(?>a|))a/utf` on `a` → no match → expected a match at 0 (Perl; the lookbehind's atomic group can match empty) | Tested: PCRE2 10.49 (C host and Erlang `re`, OTP 29). `(?<=(?:a|))a` and `(?<=(?>|a))a` match: in a variable-length lookbehind, an atomic group commits to its first branch (`a`, which would end past the current position) and never tries the empty branch. The 10.43+ lookbehind documentation gives no such restriction. Found by the round-10 campaign (mutation mode) on `erlang-re` |
| IRX-SWIFT-1 | Swift Regex | Open · [#901](https://github.com/swiftlang/swift-experimental-string-processing/issues/901) | wrong result: `/\w\b\w/` matches `"a0"`; `/0\b/` misses `"0"` → expected no; yes | Tested: Swift Regex (Swift 6.4), `.unicodeScalar` semantics + `.simple` word boundaries. `\b` treats digits as non-word although `\w` matches them; grapheme semantics is correct |
| IRX-SWIFT-2 | Swift Regex | Open · [#900](https://github.com/swiftlang/swift-experimental-string-processing/issues/900) | wrong result: `try Regex("k+").ignoresCase()` does not match `"K"` (U+212A, Kelvin), nor `"KK"` → expected match (`k` alone and `kk*` on one `K` do match) | Tested: Swift Regex (Swift 6.4), `.unicodeScalar` semantics, `ignoresCase()`. a quantified case-insensitive literal skips the Unicode case variant that the single literal honours |
| IRX-SWIFT-3 | Swift Regex | Open · [#899](https://github.com/swiftlang/swift-experimental-string-processing/issues/899) | wrong result: `\A(?:^\|a){2,}\z` and `\A(?:a\|^){2,}\z` miss `"a"` → expected match | Tested: Swift Regex (Swift 6.4), `.unicodeScalar` semantics. an open-ended counted group that needs a zero-width iteration; `{2}` and `{2,3}` are fine. Same family as IRX-JAVA-2 and IRX-ONIG-1 |
| IRX-SWIFT-4 | Swift Regex | Open · not filed | hang: `try Regex("(?:(?:^\|x)^)+").firstMatch(in: "")` never returns; also `(?:(?:\b\|x)\b)+` on `"a"`, `(?:(?:\|x)+b*)*` on `"a"` → expected `0..<0` for each | Tested: Swift Regex (Swift 6.4), default semantics and `.unicodeScalar` with simple word boundaries. A loop whose body can match empty through an alternation spins forever on empty iterations (`(?:\b)+`, `(?:(?:x\|)+a*)*` and `(?:(?:\|x)+a)*` return). One hanging case costs its whole batch, so the target allows nullable loop bodies only under `?`. Found by the feature sweep. |
| IRX-SWIFT-5 | Swift Regex | Open · not filed | wrong result: `try Regex("(?:a?(?:b\|a))b").firstMatch(in: "ab")` → `nil`; also `(?:a*(?:b\|a))b`, `(?:a??(?:b\|a))b` on `"ab"`, `(?:a?(?:b\|aa))$` on `"aa"` → expected `0..<2` | Tested: Swift Regex (Swift 6.4), default semantics and `.unicodeScalar`. Inside a group that ends in an alternation, the matcher does not backtrack into a quantifier before the alternation: `(?:a?\|c)(?:b\|a)b` and `(?:x?(?:b\|a))b` match, and so does the pattern without the outer group. Found by the feature sweep. |
| IRX-SWIFT-6 | Swift Regex | Open · not filed | wrong result: `try Regex("\\w.").matchingSemantics(.unicodeScalar).wholeMatch(in: "0\u{3A3}")` → `nil`; also `"_\u{1F600}"`, `"0\u{300}"`, `"_\u{2028}"` → expected a match (`0` and `_` are word characters) | Tested: Swift Regex (Swift 6.4), `.unicodeScalar`. `\w` misses an ASCII digit or `_` when the next scalar is U+0300 or above; before `é` (U+E9), U+2FF, `\n` or at the end it matches, and letters are unaffected (`a\u{3A3}` matches). `\d` and `[_]` are fine. Found by the round-10 campaign |
| IRX-SWIFT-7 | Swift Regex | Open · not filed | rejects valid pattern: `try Regex("[\\x{212A}-\\x{212B}]")` → "invalid bound for character class range"; also `[a-\x{212A}]`, `[\x{1FD3}-\x{1FD4}]`, `[\x{2000}-\x{2001}]`, `[\x{F900}-\x{F901}]`, `[\x{340}-\x{341}]` → expected accepted | Tested: Swift Regex (Swift 6.4), default semantics and `.unicodeScalar`. A range bound that NFC normalization changes (Kelvin sign, Ångström sign, U+1FD3, U+2000, CJK compatibility ideographs, U+0340) is rejected, even written as a hex escape; the same character as a single member (`[\x{212B}]`) is accepted. Found while probing case-insensitive ranges |
| IRX-TCL-1 | Tcl | Open · [b989a6a0e0](https://core.tcl-lang.org/tcl/tktview/b989a6a0e01c515f9889ffef2219df99108d045c) | wrong result: `regexp -nocase {^k{1}$} "\u212a"` → `0`; also `k+`, `k*`, `[k]+` → expected `1` (`regexp -nocase {^k$} "\u212a"` → `1`) | Tested: Tcl 9.1.0 (`regexp -nocase`). a quantified case-insensitive `k` loses the Kelvin-sign variant that the bare literal matches. Same as IRX-SWIFT-2; found by cross-checking |
| IRX-DOTNET-1 | .NET | Resolved · not filed | crash (exception): `Regex.IsMatch("aa", @"\A(?:(?=(?:)+?a)a)\z")` → `IndexOutOfRangeException` → expected `false` | Tested: .NET 9.0.4 Regex interpreter. **resolved in current version (.NET 11 RC 1)**; the recorded .NET 9.0.4 exception does not occur |
| IRX-DOTNET-2 | .NET | Resolved · not filed | crash at construction: `new Regex(@"\A(?:a(?<=(?:)??))\z", RegexOptions.Compiled)` → `ArgumentException: Bad label content in ILGenerator` → expected compiles, matches `"a"` | Tested: .NET 9.0.4 `RegexOptions.Compiled`. **resolved in current version (.NET 11 RC 1)**; construction and matching succeed; interpreter was already fine |
| IRX-DOTNET-3 | .NET | Resolved · not filed | wrong result: `Regex.Match("aa", @"(?:a(?:)+?)+")` → `[1,2)`; `\A(?:(?:a\|(?=a))+?){2}\z` misses `"a"`; `\A(?:(?:aa(?:)*?){2})*\z` matches `"a"×6` → expected `[0,2)`; match; no match | Tested: .NET 9.0.4 Regex interpreter. a lazy loop over a nullable body inside another loop: the outer loop iterates wrongly in both directions; Compiled and NonBacktracking are correct. **resolved in current version (.NET 11 RC 1)**; all recorded cases now give the expected result. In .NET 9.0.4 span mode also returned **impossible matches**: `Regex.Match("", @"(?:(?:)+?){2}")` → Index 0, Length 3; `Regex.Match("a", @"(?:a()+?)*")` → Index 1, Length 2 (past the end). Simplest form (no outer loop): `Regex.Match("a", @"\Aa(?:){1,}?\z")` → Index 1, Length 0 (a match starting after `\A`); `a(?:)+?$` likewise; Compiled gives `[0,1)`; on .NET 9.0.4 the match can even end past the input: `Regex.Match("A", @"(?:(?:)+?|A)+")` → Index 0, Length 3 (1-character string; .NET 11 RC 1 gives `[0,0)`; found by long span mode) |
| IRX-DOTNET-4 | .NET | Resolved · not filed | crash (exception): `new Regex(@"\A(?:(?:a\|(?:\B){2,}?)a)*a\z", RegexOptions.Compiled).Match("aaa")` → `ArgumentOutOfRangeException: Non-negative number required. (Parameter 'newSize')` → expected match | Tested: .NET 9.0.4 `RegexOptions.Compiled`. **resolved in current version (.NET 11 RC 1)**; lazy counted `\B` in an alternative inside a loop; interpreter was already correct |
| IRX-DOTNET-5 | .NET | Resolved · not filed | wrong result: `\A(?:(?:){2,3}?a)*\z` misses `"a"`; `\A(?<!(?:aa)+?)a\z` misses `"a"`; `\A(?:(?:a\|$\|(?:\B){2,}?a\|a)a)*a\z` misses `"aaaaa"` → expected match | Tested: .NET 9.0.4 `RegexOptions.Compiled`. lazy loops with a lower bound (`{2,3}?`, `+?`, `{2,}?`) inside a loop or lookbehind; `{2}?` is fine. Interpreter and NonBacktracking correct. Same area as IRX-DOTNET-4; **resolved in current version (.NET 11 RC 1)** across all three recorded cases |
| IRX-DOTNET-6 | .NET | Open · [#135586](https://github.com/dotnet/runtime/issues/135586) | wrong result: `new Regex(@"^a (?:\Ba\|\ba)+$", RegexOptions.NonBacktracking).IsMatch("a aa")` → `false`; without `$` the match is `[0,3)` → expected `true`; `[0,4)` | Tested: .NET 9.0.4 `RegexOptions.NonBacktracking`. still reproduces in .NET 11 RC 1; a loop whose alternatives start with `\b` and `\B` stops after one iteration when the pattern begins with `^`; without `^` it is correct, and the backtracking engines are correct; counted loops too: `^(?:(?:\B\|\b)a\S){3}$` misses `"a.aaaa"` (unanchored and `+` forms match) |
| IRX-DOTNET-7 | .NET | Open · [#135585](https://github.com/dotnet/runtime/issues/135585) | wrong span (differs from backtracking): `new Regex("(?:aa\|aaa)+a", RegexOptions.NonBacktracking).Match("aaaaaaaa")` → `[0,8)`; also `(?:a\|.{3,}){0,2}.` on `"abaa"` → `[0,4)` → expected `[0,7)`; `[0,2)` (the interpreter's match) | Tested: .NET 9.0.4 `RegexOptions.NonBacktracking`. still reproduces in .NET 11 RC 1; NonBacktracking takes a later, longer match when a loop has to give back an iteration. Lazy loops (`a+?`) agree there, but the r2h campaign found the same preference for a longer match with an empty or lazy alternative and with lazy counted loops: `(?:aa||a)a`, `(?:aa|a??)a`, `(?:$|a*?)a` on `"aa"` → `[0,2)` (backtracking `[0,1)`; `(?:aa|)a` agrees), `(?:a{3,}?)+a` on `"aaaaa"` → `[0,5)` (backtracking `[0,4)`), also on .NET 9.0.4. Found by span mode |
| IRX-DOTNET-8 | .NET | Open · [#135584](https://github.com/dotnet/runtime/issues/135584) | wrong span: `Regex.Match("aaaaK", @"(?:(?:a.?)+){2}")` → `[0,4)`; also `(?:(?:ab?)+){2}` on `"aaab"` → `[0,4)` → expected `[0,5)` (Perl, PCRE, Python, Java, V8) | Tested: .NET 9.0.4, all three engines (interpreter, `Compiled`, `NonBacktracking`). filed with DOTNET-6; still reproduces in .NET 11 RC 1; an exact count over a greedy loop doesn't retry the first iteration with a shorter inner match that lets the second one take more; the unrolled `(?:(?:a.?)+)(?:(?:a.?)+)` gives `[0,5)`. Full matches are right (`\A…\z` gives `[0,5)`). Found by span mode |
| IRX-DOTNET-9 | .NET | Open · not filed | wrong result (no match): `new Regex(@"b\Ba*", RegexOptions.NonBacktracking).Match("ba")` → no match; same for `b\Ba?`, `b\B[a-z]*`, `b\Bc*` on `"bc"` → expected `[0,2)` (interpreter, Compiled) | Tested: .NET 9.0.4 `RegexOptions.NonBacktracking`; still reproduces in .NET 11 RC 1. `\B` followed by a loop that can match empty: `b\Ba+` and `b\Ba*$` match correctly, and `\b` in the same position is fine. Found by the 30-minute campaign's sampled triage (`\x{17F}\Ba*` on `"ſa"`) |
| IRX-DOTNET-10 | .NET | Open · not filed | wrong span (not leftmost): `new Regex(@"(?:b\B|ek)+", RegexOptions.NonBacktracking).Match("bek")` → `[1,3)`; also `(?:b\b|.[a-z])+` on `"b ek"` → `[1,3)` → expected `[0,3)` (interpreter, Compiled, PCRE2) | Tested: .NET 9.0.4 and .NET 11 RC 1 `RegexOptions.NonBacktracking`. A loop whose alternative ends with `\b`/`\B`: the match that starts with that alternative is missed and a later start is reported; without the loop (`b\B(?:ek)`) it is correct. Compare IRX-DOTNET-6 (alternatives starting with `\b`/`\B`) and IRX-DOTNET-9. Found by the long-input campaign (span mode), minimized to `(?:\x{17F}\B|.[a-z])+` on `"ſék"` |
| IRX-DOTNET-11 | .NET Regex (interpreter, Compiled) | Open · not filed | wrong result: `Regex.IsMatch("aa", @"^(?>a+){2}$")` → `true`; also `^(?:(?>a+)){2}$` on `"aa"`, `^(?>a+){2}$` on `"aaa"`, `^(?>[^b]+){2}$` on `"aa"` → expected `false` (the atomic `a+` takes every `a` and gives none back; PCRE2, Perl); and the reverse, `^(?>a?)+a$` on `"aa"` → `false` → expected `true` (the loop gives back its last atomic iteration) | Tested: .NET 9.0.4, 10.0.12 and 11.0.0-rc.1 (interpreter and Compiled; NonBacktracking rejects atomic groups). `(?>a+)(?>a+)` and `(?>a+)a` are correct: only an atomic group as a loop body goes wrong. Found by the round-10 campaign (mutation mode) on `dotnet-compiled` |
| IRX-DOTNET-12 | .NET Regex (interpreter, Compiled) | Open · not filed | wrong result: `Regex.IsMatch("aa", @"^\D+\Ba$")` → `false`; also `\D{1,2}\Ba` and `\D+?\Ba` on `"aa"`, `\D+\Bb` on `"ab"`, `\W+\B ` on `"  "` → expected `true` (.NET 9.0.4, NonBacktracking, PCRE2, Perl) | Tested: .NET 10.0.12 and 11.0.0-rc.1 (interpreter and Compiled); .NET 9.0.4 and NonBacktracking are correct. A loop over `\D` or `\W` followed by `\B` never gives back characters, as if made atomic: `\D\Ba`, `[^0-9]+\Ba`, `a+\Ba`, `.+\Ba` and `\D+\ba` on `"-a"` are correct. Found by the r2h campaign (2 hours) on `dotnet-compiled` |
| IRX-DOTNET-13 | .NET Regex (interpreter, Compiled) | Open · not filed | wrong result (no match): `Regex.Match("", @"(?:a+|)+")` → no match; also `(?:a+|){1,2}` on `""` and `"."`, `(?:a+|){1,2}b` on `"b"`, `(?:|a+?)+?` on `""`, `a(?:a{1,2}|){1,}` on `"a"`; and `(?:(?:)|(?:aa){1,2}?){1,2}?` on `"aaaaaaaa"` → `[0,2)` → expected `[0,0)` each time (.NET 9.0.4, PCRE2, Perl) | Tested: .NET 10.0.12 and 11.0.0-rc.1 (interpreter and Compiled); .NET 9.0.4 is correct. A loop with minimum ≥ 1 whose body alternates a loop with an empty branch acts as if the empty branch were absent: `(?:a|)+`, `(?:a+|)*`, `(?:a+|)?` and `(?:a+|())+` (capture in the empty branch) are correct. Found by the r2h campaign (2 hours) on `dotnet-compiled` |
| IRX-DOTNET-14 | .NET Regex (interpreter) | Open · not filed | crash (exception while matching): `new Regex(@"(?!\d()?|\d)").Match("")` → `OverflowException: Arithmetic operation resulted in an overflow`; `new Regex(@"a|(?!\d()?|\d)").Match("_")` → `IndexOutOfRangeException` → expected `[0,0)` (.NET 9.0.4, 10.0.12, Compiled) | Tested: .NET 11.0.0-rc.1 interpreter (default options and `ECMAScript`); .NET 9.0.4 and 10.0.12 and `RegexOptions.Compiled` are correct. A negative lookahead whose first alternative ends in an optional empty capture and has a second alternative: `(?!\d()?)`, `(?!\d()|\d)` and `(?!()?|\d)` are fine. Found by the r2h campaign (2 hours) on `dotnet-ecma` |
| IRX-DOTNET-15 | .NET Regex (interpreter, Compiled) | Open · not filed | crash (exception while matching): `new Regex(@"(?!a(?:()()|()))").Match("a")` → `ArgumentOutOfRangeException: Index was out of range` (also on `""`) → expected `[1,1)`; `[0,0)` (.NET 9.0.4) | Tested: .NET 10.0.12 and 11.0.0-rc.1, interpreter and Compiled; .NET 9.0.4 is correct (regression). A negative lookahead whose alternatives hold different numbers of capture groups after a consuming item: `(?!a(?:()|()))`, `(?!a(?:()()|))`, `(?!a()())` and `(?!(?:()()|()))` are fine. Found by the r2h campaign (2 hours) on `dotnet-interp` |
| IRX-XS-2 | XS | Open · [#1752](https://github.com/Moddable-OpenSource/moddable/issues/1752) | wrong result: `/^[S\u{1F600}]$/iv.test("s")` → `false`; `/^[^A]$/iv.test("a")` → `true` → expected `true`; `false` | Tested: XS (jsvu, Moddable). `v`-mode classes ignore `i`: neither members nor complements are case-folded (~250 findings) |
| IRX-XS-3 | XS | Not a bug · not filed | parse-time `RangeError: buffer overflow` on large batches: XS rejects a script when one string literal's source reaches 64K characters (65,535 → `string overflow`, 65,536+ → `buffer overflow`); the bridge embedded each batch as one JSON string literal, and 512-case batches full of `\u` escapes crossed it | Harness artifact, found 2026-10-12: the abort happened while parsing, before any case ran, so the per-case `try` never applied and it looked sequence-dependent. Same in `xst` built from `5f215f7`. An XS implementation limit (Moddable treats such limits as fail-fast by design; see their reply on #1707), so not reported. `tools/bridge.py` now writes the batch as concatenated literals of at most 4,096 characters; the recorded batch (5m-xs finding 1467) now returns all 512 results |
| IRX-XS-4 | XS | Open · [#1753](https://github.com/Moddable-OpenSource/moddable/issues/1753) | wrong result: `/^(?:(?:a+){1}){2}$/.test("aa")` → `false` → expected `true` | Tested: XS (jsvu, Moddable). the IRX-BOA-7 / IRX-HERMES-3 shape (counted repeat of a counted greedy loop); `(?:(?:a+)+){2}` is fine here. Found by cross-checking. |
| IRX-XS-5 | XS | Open · [#1755](https://github.com/Moddable-OpenSource/moddable/issues/1755) | wrong result: `/^(?:a\|^){2}$/.test("a")` → `false`; `/^(?:a\|\B){3}$/.test("aa")` → `false` → expected `true` | Tested: XS (jsvu, Moddable). a counted group needing a zero-width iteration; `{2,}` is fine. Same family as IRX-JAVA-2, IRX-ONIG-1, IRX-SWIFT-3 |
| IRX-XS-6 | XS | Open · [#1756](https://github.com/Moddable-OpenSource/moddable/issues/1756) | wrong result: `/^(?:(?:aa(?:)*?){2})*$/.test("aaaaaa")` → `true` → expected `false` | Tested: XS (jsvu, Moddable). a lazy loop over an empty group inside a counted group miscounts; without `(?:)*?` it is correct. Same shape as one IRX-DOTNET-3 case. Found by cross-checking |
| IRX-XS-7 | XS | Open · [#1757](https://github.com/Moddable-OpenSource/moddable/issues/1757) | hang: `/(?:a?)*b/.test("a")` and `/(?:a\|)*b/.test("a")` never return; also `/^(?:^a?)+?$/.test("aa")` → expected `false` | Tested: XS (jsvu, Moddable). a star over a nullable body that fails after it loops forever; `(?:\|a)*b` and `(?:)*b` are fine. Found by cross-checking IRX-BOA-8 |
| IRX-XS-8 | XS | Open · [#1758](https://github.com/Moddable-OpenSource/moddable/issues/1758) | wrong result / wrong span: `/(?:a\|a){3}/.exec("aa")` → `"aa"`; `/^(?:a\|a){3}$/.test("aa")` → `true`; `/(?:a{2,}){3}/.exec("aaaa")` → `"aaaa"` → expected `null`; `false`; `null` | Tested: XS (jsvu, Moddable). a counted group over alternatives that can match the same text is satisfied too early; `(?:a\|b){3}` is correct. Found by span mode |
| IRX-XS-9 | XS | Open · [#1759](https://github.com/Moddable-OpenSource/moddable/issues/1759) | wrong capture: `/(a\|)*c/.exec("ac")` → `["ac", undefined]`; `/(a*)+/.exec("b")` → `["", undefined]` → expected `["ac", "a"]`; `["", ""]` (V8, QuickJS, Boa, Hermes) | Tested: XS (jsvu, Moddable). when a loop's next iteration is rejected, the captures of the last successful iteration are dropped instead of restored. Found while researching phase 2 ([docs/phase2-captures.md](docs/phase2-captures.md)) |
| IRX-XS-10 | XS | Open · [#1760](https://github.com/Moddable-OpenSource/moddable/issues/1760) | wrong span: `/(?:\|a)*/.exec("a")` → `[""]`; `/(?:a*?)*/.exec("a")` → `[""]` → expected `["a"]` (V8, QuickJS; ES RepeatMatcher rejects an empty iteration once min is met) | Tested: XS (jsvu, Moddable). XS accepts the empty iteration and leaves the loop, as Perl/PCRE do, instead of rejecting it and trying the other branch. Found by span mode |
| IRX-XS-11 | XS | Open · [#1761](https://github.com/Moddable-OpenSource/moddable/issues/1761) | wrong match indices: `/A/d.exec("éA").indices[0]` → `[1,1]`; `/A/d.exec("\u212AA").indices[0]` → `[1,0]` (end before start); `/A/d.exec("😀A").indices[0]` → `[2,2]` → expected `[1,2]`; `[1,2]`; `[2,3]` (V8) | Reproduces in jsvu XS 17.9.3 and in `xst` built from current Moddable `public` source at `5f215f7` (2026-10-09). With `d`, end offsets are wrong after non-ASCII text; `m.index` and `m[0]` are correct |
| IRX-E262-1 | engine262 | Open · [#370](https://github.com/engine262/engine262/issues/370) | rejects valid pattern: `new RegExp("[\\u{17F}--\\u{212A}]", "v")` → SyntaxError "Expect a CharacterClassEscape" → expected accepted | Tested: npm `@engine262/engine262` commit `678c2c0` (2026-10-03), which matches current upstream `main`. The doubled backslashes in the JS string pass literal Unicode escapes to the RegExp parser; the previous single-backslash example was accepted because JS decoded it before RegExp construction. A `\u{…}` escape is rejected as a `ClassSetOperand` in set operations. |
| IRX-E262-2 | engine262 | Open · [#371](https://github.com/engine262/engine262/issues/371) | wrong result: `/^[^[^a]&&\d]$/v.test("ſ")` → `false`; `/^a[^A&&[a-z]]$/v.test("aa")` → `false` → expected `true`; `true` | Tested: engine262 (npm `@engine262/engine262`). negated classes whose contents are a set operation are computed wrongly (~46k findings) |
| IRX-E262-3 | engine262 | Open · [#372](https://github.com/engine262/engine262/issues/372) | wrong result: `/\u{1F600}\B/u.exec("😀k")` → match `[0,2)`; `/\W\b/u.exec("😀k")` → `null` → expected `null`; `[0,2)` (V8) | Tested: engine262 (npm `@engine262/engine262`). In `u` mode a word boundary right after an astral character is evaluated wrongly (it behaves as if there were no boundary between `😀` and `k`); BMP characters (`é`) and the `v` flag are fine. Found by the long-input campaign (span mode), minimized to `(?:\W\B|[A-Z])*` on `"😀k"` |
| IRX-E262-4 | engine262 | Open · not filed | wrong result: `/^.$/iv.test("a")` → `false`; also `/^[^b]$/iv` on `"a"`, `/^\W$/iv` on `"-"` → expected `true` (each is `true` under `v` and under `iu`; `/^\S$/iv` and `/^a$/iv` work) | Tested: engine262 (npm `@engine262/engine262` commit `678c2c0`). With both `i` and `v`, every set built by complement (`.`, negated classes, `\W`) matches nothing (`\P{Lu}` correctly misses `"a"`: under `v` it is the complement of the case-folded `\p{Lu}`, which holds `a`); the spec applies no case folding to `.` at all. The engine262 target drops the `iv` flag sets so the rest of `v` mode stays visible. |
| IRX-E262-5 | engine262 | Open · not filed | wrong result: `/^[[a-z]&&a]$/v.test("b")` → `true`; also `[a&&[a-z]]` and `[\p{L}&&a]` on `"b"`, `[[a-z]--a]` and `[\p{L}--a]` on `"a"` → expected `false` (V8) | Tested: engine262 (npm `@engine262/engine262`). A non-negated set operation with a range or property operand returns that operand unchanged (the `&&`/`--` is ignored); operations on listed characters (`[[ab]&&[bc]]`) and `[\w&&a]` are correct. Separate from IRX-E262-2 (negated classes). Found by the r2h campaign (2 hours) on `engine262` |
| IRX-FANCY-1 | fancy-regex | Resolved · not filed | wrong capture: `fancy_regex::Regex::new(r"(?:(?:(a)|b)(?=)){2}")?.captures("ab")` → group 1 `None`; also `(?:(?:b|(a))(?=a)a){2}` on `"aaba"` → expected `Some(0..1)`; `Some(1..2)` (fancy-regex without the lookahead, `regex`, PCRE2, Perl) | Tested: fancy-regex 0.14. **Fixed in 0.19.2** (2026-10-12: all three patterns give group 1 `Some(0..1)`, matching PCRE2). When a loop body contains a lookaround, the backtracking VM forgets a capture set by an earlier iteration once a later iteration takes a branch without it (ES-style reset); the same pattern without the lookaround is delegated to `regex` and keeps it, so equivalent patterns disagree. Found in capture mode; a second trigger without lookarounds (found by long capture mode): `(?:(?:^(b)|\D)\Ba)*` on `"baba"` → group 1 `None`, expected `Some(0..1)` (needs both `^` and `\B` in the body; `regex` correct) |
| IRX-FANCY-2 | fancy-regex | Open · not filed | wrong span (regression): `fancy_regex::Regex::new(r"(a+?)*")?.find("aaa")` → `0..1`; also `(?:(a+?))*`, `(a+?){0,}`, `(?:(?:a+?)+)*` on `"aa"` → `0..1` → expected `0..3`; `0..2` (fancy-regex 0.19.0 and earlier, `regex`, Perl) | Tested: fancy-regex 0.19.1 and 0.19.2 (0.14–0.19.0 correct). A greedy loop over a lazy loop stops after one iteration when the body is a capture group or another loop; non-capturing `(?:a+?)*` is fine. Found by the round-10 re-run on 0.19.2 |
| IRX-FANCY-3 | fancy-regex | Open · not filed | wrong result (regression): `fancy_regex::Regex::new(r"^(?:(?:a|\B){2,}){2}$")?.is_match("aa")` → `false`; `(?:(?:a|\B){2,}){2}` finds `0..1` in `"aa"` → expected `true`; `0..2` (fancy-regex 0.15 and earlier, Perl, PCRE2, Python `re` and `regex`: the first round takes `a` then `\B`, the second `\B` then `a`) | Tested: fancy-regex 0.16.2–0.19.2 (0.11–0.15.0 correct). An unbounded inner repeat whose first iteration in a later outer iteration matches empty where the previous one ended: `{2}`, `+` or `(?:)` in place of `\B` match |
| IRX-RLITE-1 | regex-lite | Open · not filed | wrong result: `regex_lite::Regex::new(r"(?i)^[[:^upper:]]$")?.is_match("a")` → `true`; also `"A"` → `true`, and `(?i)[[:^lower:]]` on `"a"` → expected `false` (the `regex` crate; `(?i)[^[:upper:]]` and `(?i)[^A-Z]` give `false` in regex-lite too) | Tested: regex-lite 0.1.9. A negated POSIX class is case-folded after negation, so under `i` it matches every letter, while a negated bracket class folds first. Found by the Rust model completion (POSIX classes); the `rust-lite` dialect keeps negated POSIX classes out of `i` |
| IRX-GRAAL-1 | GraalJS | Open · not filed | wrong result: `/^(?:a-(?:(?:(?:\b\|\b)(?:)a)?){1,2}){2}$/.test("a-a-")` → `false`; also `{1,2}` for the outer count → expected `true` (V8, SpiderMonkey) | Tested: GraalJS community 25.4.4.1.1 (TRegex, macOS aarch64 native image). Needs the counted outer loop, the inner `{1,2}`, the `\b\|\b` alternation and the empty group together: `(?:\b\|\b)a`, `\b(?:)a`, `(?:\b\|x)(?:)a`, an outer `+` or an uncounted inner group all match. Found by the new `graaljs` target's sweep. |
| IRX-GRAAL-2 | GraalJS | Open · not filed | wrong result: `/^A\b/u.test("A😀")` → `false`; `/^\B/u.test("😀")` → `false` → expected `true`; `true` (V8 15.6, Bun 1.4.2) | Tested: GraalJS 25.4.4.1.1 (TRegex). Under `u`, neither `\b` nor `\B` holds at a position next to an astral character (both assertions fail there); without `u` both are correct. Found by the r2h campaign self-check on `graaljs` (60 mismatches) |
| IRX-GRAAL-3 | GraalJS | Open · not filed | wrong result: `/^[\W--\p{L}]$/iv.test("Σ")` → `true`; also `[\W--[^a]]` → expected `false` (V8 15.6, Bun 1.4.2; GraalJS itself gives `false` under `v`) | Tested: GraalJS 25.4.4.1.1 (TRegex). Under `iv`, a set difference whose left side is `\W` keeps characters that the right side removes; `/^\W$/iv.test("Σ")` is correctly `true`. Found by the r2h campaign on `graaljs` |
| IRX-HERMES-1 | Hermes | Open · [#2235](https://github.com/facebook/hermes/issues/2235) | wrong result: `/^(?:(?:(?:\W+){1,1})*\s)$/.test("\u2028\n")` → `false` → expected `true` | Reproduces in the v0.13.0 CLI and a source build from current `260318099.0.0-stable` at `09d3bf2` (2026-10-08). Boa also fails it (cross-check) |
| IRX-HERMES-2 | Hermes | Open · [#2234](https://github.com/facebook/hermes/issues/2234) | exception on tiny input: `/^(?:(?:^a?)+?)$/.test("aa")` → `RangeError: Maximum regex stack depth reached` → expected `false` | Reproduces in the v0.13.0 CLI and current stable source build `09d3bf2`. Also `(?:a*)+?\B` on `"a"`, `(?:(?:(?:)\|(?:)){2,2}){1,2}` on `"a"`: lazy loops over empty-matchable bodies recurse without bound |
| IRX-HERMES-3 | Hermes | Open · [#2232](https://github.com/facebook/hermes/issues/2232) | wrong result: `/(?:(?:a+){1}){2}/.test("aa")` → `false`; `/^(?:(?:a{2,}){2}){2}$/.test("a".repeat(8))` → `false` → expected `true` | Reproduces in the v0.13.0 CLI and current stable source build `09d3bf2`. A counted repeat of a group whose body is a counted repeat of a greedy loop; same shape as IRX-BOA-7 |
| IRX-HERMES-4 | Hermes | Open · [#2233](https://github.com/facebook/hermes/issues/2233) | wrong result: `/a(?<=x\|^a)/.test("a")` → `false` → expected `true` | Reproduces in the v0.13.0 CLI and current stable source build `09d3bf2`. `^` inside an alternative of a lookbehind; `a(?<=^a)` and `a(?<=x\|a)` are fine |
| IRX-RACKET-1 | Racket | Open · [#5605](https://github.com/racket/racket/issues/5605) | crash at construction: `(pregexp "(?:)(?:)")` → `exn:fail` "invalid memory reference. Some debugging context lost" → expected compiles; matches `""` | Tested: Racket 9.3 CS (`regexp`/`pregexp`/`byte-pregexp`). two or more adjacent empty non-capturing groups (also `a\|(?:)(?:)`, `^(?:(?:)(?:))$`); `()()`, `(?:(?:))`, `(?:)a(?:)` are fine, and a `#rx` literal `x(?:)(?:)y` works. The message is Chez Scheme's memory-fault handler |
| IRX-RACKET-2 | Racket | Semantics question · [#5608](https://github.com/racket/racket/issues/5608) | `(regexp-match? #px"^b(?<=b(?=a))a$" "ba")` → `#f`; `#px"(?<=(?=a))"` never matches; `#px"^(?<!(?!a))a$"` misses `"a"` | Tested: Racket 9.3 CS (`#px`). Nested lookahead appears bounded by the lookbehind's input, while `$` still refers to the original input end. Both `^b(?<=b(?=a))a$` and `^b(?<=b(?=$))a$` return `#f` on `"ba"`; this is consistent under that interpretation. #5608 asks whether it is intended; do not count this as a confirmed bug |
| IRX-RACKET-3 | Racket | Open · [#5607](https://github.com/racket/racket/issues/5607) | wrong result: `(regexp-match? #px"^[^ſ]$" "ß")` → `#f`; also `"é"` → `#f` → expected `#t` (neither is `ſ`) | Tested: Racket 9.3 CS (`#px`). A negated class containing `ſ` (U+017F, UTF-8 `C5 BF`) also excludes other two-byte characters; `[^ā]`, `[^Ā]` and `[^K]` are fine, so the `BF` continuation byte seems to break the byte-level complement. Possibly the same root as RACKET-1 (non-ASCII ranges losing members). Found by the long-input campaign, minimized to `[^\x{17F}\x{D}]{0,}` on `"-ß"` |
| IRX-RACKET-4 | Racket | Open · [#5609](https://github.com/racket/racket/issues/5609) | wrong result: `(regexp-match? #px"^\\p{C}$" "😀")` → `#t`; also U+1F601 and U+FFFD (category So) → `#t`, and U+E000 (Co, private use) → `#f` → expected `#f`; `#f`; `#t` | Tested: Racket 9.3 CS (`#px`). `\p{C}` (Other) matches some So characters and misses Co ones, although `(char-general-category #\U1F600)` is `so` and `\p{So}`, `\p{S}` and `\p{Cc}` are correct. Found by the self-check of the new `\p{…}` atoms |
| IRX-RACKET-5 | Racket | Open · not filed | wrong result: `(regexp-match-positions #px"(?<!.)a" "éa")` → `((1 . 2))`; also `#px"(?<![^b])a"` on `"éa"`, `#px"(?<!\\S)a"` on `"\u200Ba"`, `#px"é(?<!.)"` on `"é"` → expected `#f` (`#px"(?<!.)a"` on `"xa"` → `#f`) | Tested: Racket 9.3 CS (`#px`, string input). A negative lookbehind whose set includes a multi-byte character by class (`.`, `[^b]`, `\S`) does not see a multi-byte character right before it; naming the character (`(?<!é)`, `(?<![é])`) works, and positive lookbehinds are fine. Found by pool rotation (spaces/invisibles pool). |
| IRX-LLVM-1 | LLVM | Open · not filed | wrong result (not leftmost): `Regex("(()\|a)b").match("ab", &m)` reports `[1,2)`; `(()\|a)$` on `"a"` reports `[1,1)` → expected `[0,2)`; `[0,1)` | Tested: LLVM 23.1.2 `llvm::Regex` (BSD/Spencer ERE). a match starting at 0 exists but is skipped when the first alternative can be empty (also `(x*\|a)$`); `(a\|())$` is fine. With REG_NEWLINE it turns full-match checks into misses |
| IRX-LLVM-2 | LLVM | Open · not filed | wrong result: `Regex("(^){2}x").match("x")` → false; `(^){2}` misses `""` → expected true | Tested: LLVM 23.1.2 `llvm::Regex` (BSD/Spencer ERE). an exact count on a group holding an anchor never matches (`(^){2}`, `($){2}`); `(^)(^)`, `(^){1,2}`, `(^)+` and `(()){2}` are fine |
| IRX-LIBCXX-1 | libc++ `std::regex` | Open · not filed | wrong result: `std::regex_search("a\nb", std::regex("a\\n^b", ECMAScript \| multiline))` → no match; also `\\n^b` on `"\nb"`, `[\\s\\S]^` on `"\nb"` → expected `[0,3)`; `[0,2)`; `[0,1)` (`x\\n^b` on `"yx\nb"` → `[1,4)`) | Tested: libc++ 22.1 (Xcode, `_LIBCPP_VERSION` 220106). Under `multiline`, `^` fails after a line terminator consumed earlier in the same match attempt when that attempt started at position 0. Found by the new `cpp-regex` target's self-check. |
| IRX-LIBCXX-2 | libc++ `std::regex` | Open · not filed | wrong result: `std::regex_match("a", std::regex("a(?=\\b)"))` → false; `std::regex_match("ab", std::regex("a(?!\\B)b"))` → true → expected true; false | Tested: libc++ 22.1 (Xcode). Inside a lookahead, `\b` and `\B` ignore the character before the lookahead position, as if the lookahead started a new string. Found by the new `cpp-regex` target's sweep. |
| IRX-LIBCXX-3 | libc++ `std::regex` | Open · not filed | wrong result: `std::regex_search("a", m, std::regex("\\B"))` → match `[1,1)` → expected no match (both positions of `"a"` are word boundaries) | Tested: libc++ 22.1 (Xcode). `\B` holds at the end of the string after a word character. Found by the new `cpp-regex` target's sweep. |
| IRX-LIBCXX-4 | libc++ `std::regex` | Open · not filed | wrong result: `std::regex_match("", std::regex("(a)?\\1"))` → false; also `(a)a\|\1` on `""`, `(?:(a)\|b)\1` on `"b"` → expected true (ECMAScript, including the 3rd edition the C++ standard cites: a backreference to a group that did not participate matches empty) | Tested: libc++ 22.1 (Xcode). Found by mutation mode (backreferences) on the `cpp-regex` target; the `cpp` dialect follows libc++ here so the target keeps finding other bugs. |
| IRX-LIBCXX-5 | libc++ `std::regex` | Open · not filed | rejects valid pattern: `std::regex("(a)(?=\\1)a")` → `regex_error` "invalid back reference"; also `(a)(?!\1)b` and any backreference inside a lookahead → expected accepted (ECMAScript allows backreferences in lookaheads, including the 3rd edition the C++ standard cites) | Tested: libc++ 21 (Xcode) and libc++ 23.1.2 (Homebrew LLVM). A backreference outside a lookahead (`(a)\1`) compiles. Found by the round-10 campaign (mutation mode) on `cpp-asan`; the `cpp` dialect no longer places backreferences in lookarounds |
| IRX-LIBC-1 | macOS libc regex (TRE) | Open · not filed | wrong result: `regexec` of `^(($)*a)$` (`REG_EXTENDED`) on `"a"` → no match; also `^(a(^)*)$`, `^(a(^)?)$`; `echo a \| grep -E '($)*a'` → no match → expected match (zero iterations; `^((^)*a)$` and LLVM's Spencer regex match) | Tested: macOS 27 libc (`regcomp`/`regexec`, `/usr/bin/grep -E`). A quantified group holding `$` before other content, or `^` after it, makes the match fail even when it can repeat zero times. The `libc` dialect stops generating quantified assertions so the target can find other bugs. Found by the new `libc-regex` target's sweep. |
| IRX-LIBC-2 | macOS libc regex (TRE) | Open · not filed | wrong span (not leftmost): `regexec` of `aa\|a{2}` (`REG_EXTENDED`) on `"aaa"` → `[1,3)`; `.a\|a+` on `"Aaa"` → `[1,3)` → expected `[0,2)` for both (POSIX: the leftmost match, then the longest) | Tested: macOS 27 libc (`regcomp`/`regexec`). With an alternation, a longer-looking match at a later start beats the leftmost one. Found by the new `libc-regex` target's span mode. |
| IRX-JAVA-1 | Java | Resolved · not filed | wrong result (asymmetric case folding): `Pattern.compile("ß", CASE_INSENSITIVE \| UNICODE_CASE).matcher("ẞ").matches()` → false → expected true (`Pattern.compile("ẞ", …).matcher("ß")` is true) | Tested: OpenJDK 23 `java.util.regex` (`CASE_INSENSITIVE \| UNICODE_CASE`). **resolved in current version (OpenJDK 27)**; ß and ẞ now match in both directions, including the class case; older OpenJDK 23 behavior is retained here |
| IRX-JAVA-2 | Java | Partly resolved · not filed | wrong result: `Pattern.matches("(?:a\|^){2}", "a")` → `false`; also `(?:a\|\B){3}` on `"aa"`, `(?:(?=a)\|a){2}` on `"a"`, `(?:^a*){2}` on `"a"` → expected `true` | Tested: OpenJDK 23 `java.util.regex`. a counted group where one iteration is a zero-width assertion stops counting; **resolved in current version (OpenJDK 27)** for these recorded variants; JAVA-2 has a different counted-loop form that still fails. In OpenJDK 23 an empty alternative and the unrolled form were correct. Related behavior remains in Ruby/Oniguruma (IRX-ONIG-1), Swift (IRX-SWIFT-3) and XS (IRX-XS-5) |
| IRX-JAVA-3 | Java | Open · not filed | wrong result: `Pattern.compile("(?<=a*a*)").matcher("a").find()` → `false`; `a(?<=a*b*)` misses `"a"` → expected `true` | Tested: OpenJDK 23 `java.util.regex`. a lookbehind with two unbounded parts never matches (likely overflow of the summed maximum length); `(?<=a*)` and `(?<=a?a*)` are fine |
| IRX-JAVA-4 | Java | Open · not filed | wrong capture: `(?:(a)+){2}` on `"aaa"` → group 1 `[1,2)`; `a{0,}(?=a\|(()))a` on `"a"` → group 1 `[1,1)`; `(?:(?:()a){2}){0,}` on `"a"` → group 1 `[0,0)`; `a()*` on `"a"` → group 1 unset → expected `[2,3)`; unset; unset; `[1,1)` (Python, PCRE2) | Tested: OpenJDK 23 `java.util.regex`. captures inside loops are not kept in step with backtracking: values from abandoned attempts survive, and the iteration that actually completed is not the one recorded. Found by capture mode (phase 2) |
| IRX-JAVA-5 | Java | Open · not filed | wrong result: `Pattern.compile("(?<=\\x{1F600})").matcher("😀").find()` → `false`; also `.(?<=[_\x{1F600}])`, `(?<=\p{So})` on `"😀"` → expected `true` (match at 2) | Tested: OpenJDK 23, 25 and 27 `java.util.regex`. A lookbehind whose astral character comes from an escape or property never matches; the same lookbehind with the literal character (`(?<=[_😀])`), and `(?<=.)` or `(?<=[^a])`, work, which suggests the lookbehind's length is computed in code points for the escape but checked in UTF-16 units. Found by span mode (`a.(?<![^_\x{1F600}])` on `"a😀"`) |
| IRX-JAVA-6 | Java | Open · not filed | wrong capture: `Pattern.compile("x(?!(y))").matcher("xyxz")` → match `[2,3)` with group 1 `[1,2)`; also `a(?!(.))` on `"ab a"` → group 1 `[1,2)` → expected group 1 unset (Python, PCRE2) | Tested: OpenJDK 23 and 27 `java.util.regex`. A group inside a negative lookahead keeps the value it got in an earlier, failed match attempt at another start position; no loop needed (compare IRX-JAVA-4). Found by long capture mode, minimized to `[^\x{3C2}.](?!(?<g1>.))` on `"\rA"` |
| IRX-JAVA-7 | Java | Open · not filed | wrong span (starts before the region): `m = Pattern.compile("(?<=^aa)").matcher("aa"); m.region(2, 2); m.useTransparentBounds(true); m.useAnchoringBounds(false); m.lookingAt()` → `[0,2)`; also `a|(?<=^a)` from 1 on `"a"` → `[0,1)` → expected `[2,2)`; `[1,1)` (`find()` on the same region gives them; `(?<=aa)` without `^` is right) | Tested: OpenJDK 21.0.11, 25.0.4.1, 27 and Oracle JDK 23.0.2. A `^` inside a lookbehind overwrites the match start that `lookingAt()` reports. Found by the round-10 campaign (sticky mode) on `java` |
| IRX-ICU-1 | ICU | Open · not filed | hang: `NSRegularExpression(pattern: "a(?:)*?b").firstMatch(in: "ac", …)` never returns; also `a(?:\b)*?b` on `"a b"`, `a(?:(?=c))*?b` on `"ac"`, `.(?:$)*?.` on `"k\n"` with `anchorsMatchLines` → expected `nil` | Tested: ICU regex (macOS 27 `libicucore`, via `NSRegularExpression`). a lazy unbounded loop (`*?`, `+?`) whose body matches empty, when what follows fails; greedy `*` and bounded `{0,3}?` are fine. Every 10-minute ICU batch hit one; also hangs on `(?:^a?)+?` vs `"aa"` (the IRX-HERMES-2 shape) and `(?:(?:aa(?:)*?){2})*` |
| IRX-ICU-2 | ICU | Open · not filed | wrong result: `^(?:(?:)\|a)*?$` on `"a"` → no match; `(?:()\|a)+?b` on `"ab"` → no match; also `^(?:a??)*?$`, `^(?:a*?)+?$` → expected match | Tested: ICU regex (macOS 27 `libicucore`, via `NSRegularExpression`). a lazy loop whose body can match empty and tries the empty branch first never advances; `(?:a\|(?:))*?` (consuming branch first) and greedy `*` are fine. Related to IRX-ICU-1, which hangs instead. Found once ICU could run (hangs now time out per match) |
| IRX-ICU-3 | ICU | Open · not filed | wrong result: `^ a(?<=(?:a\|\b){2})K$` on `" aK"` → no match; also `{1,2}`, and `(?:a\|^){1,2}` → expected match (V8) | Tested: ICU regex (macOS 27 `libicucore`, via `NSRegularExpression`). a counted repeat (other than `{1}`) of an alternation whose later branch is zero-width, inside a lookbehind; the unrolled `(?:a\|\b)(?:a\|\b)?` and `(?:\b\|a){1,2}` work |
| IRX-ICU-4 | ICU | Open · not filed | wrong result (missed match): `(?:a\|\Bx)?\B` on `"a "` → no match; `(?:a\|\Bx)*\B`, `(?:[^K]\|\Ba)*\B` likewise → expected empty match at 2 (V8) | Tested: ICU regex (macOS 27 `libicucore`, via `NSRegularExpression`). an optional or repeated group with a branch that starts with `\b`/`\B`, followed by `\B`: the empty match at the end is never tried, likely a start-position optimization; `(?:a\|x\B)*\B` and `.*\B` are fine. Found by span mode once ICU could run |
| IRX-ICU-5 | ICU | Open · not filed | wrong result (missed match): `a\b\b` on `"a"` → no match; `^a \B\B$` on `"a "` → no match; `\B\B` on `"a "` → no match (search) → expected `[0,1)`; `[0,2)`; empty match at 2 (V8) | Tested: ICU regex (macOS 27 `libicucore`, via `NSRegularExpression`). two consecutive word-boundary assertions at the end of the input: one alone works (`a\b`, `^a \B$`), and the doubled form works on some strings (`^ab\b\b$` on `"ab"`, `^  \B\B$` on `"  "`); `\b(?:)\b` and `(?:\b){2}` fail the same way. Found by the 30-minute campaign's sampled triage (`[^b\x{17F}]*\B\B` on `"a "`); distinct from IRX-ICU-4 (no group, and anchored forms fail too) |
| IRX-ICU-6 | ICU | Open · not filed | hang: `uregex_find` with `(?:)*+` on `"a"` never finishes (hits the match time limit); also `()*+`, `(?:a?)*+`, `(?:)++a`, `x?(?:)*+a` → expected an empty match at 0 (or `[0,1)` for the `a` forms; PCRE2, Perl, Java) | Tested: ICU4C 78.3 (`uregex`, time limit 50) and `NSRegularExpression` on macOS 27 (reports no match). A possessive quantifier over a body that can match empty loops forever; the lazy form is IRX-ICU-1. Found by the round-10 campaign (mutation mode, possessive) on `icu` |
| IRX-ICU-7 | ICU | Open · not filed | wrong result (inconsistent full case folding in sets): `(?i)[\x{FB00}]` matches `"ff"` (also `(?i)[\x{FB01}]` on `"fi"`), but `(?i)[\x{FB00}a]` does not match `"ff"` and `(?i)[\x{DF}]` does not match `"ss"` (while the literal `(?i)\x{DF}` does) → expected one rule for every set: a class matches one character (simple folding), so `[\x{FB00}]` should not match `"ff"` | Tested: ICU4C 78.3 (`uregex`, UREGEX_CASE_INSENSITIVE) and macOS 27.0.1 `NSRegularExpression`. Whether a set matches a multi-character fold depends on its other members: a one-member set of a ligature behaves like the literal. Found by the r2h campaign on `icu-c` |
| IRX-ONIG-1 | Onigmo / Oniguruma | Open · [#22430](https://bugs.ruby-lang.org/issues/22430) (Ruby) | wrong result: `/\A(?:^a*){2,3}\z/.match?("a")` → `false`; Ruby also: `\A(?:a\|^){2,3}\z` on `"a"`, `\A(?:\B\|a){3}\z` on `"aa"`; Oniguruma also: `\A(?:^a{0,2}){2}\z` → expected `true` | Tested: Ruby 4.0.7 (Onigmo) and Oniguruma 6.9.10. a counted group needing a zero-width iteration (`^`, `\B`, or a body that gives back its characters) to reach its count. Ruby's `\A(?:a\|^){2}\z` is fine but `{2,3}` is not. Same idea as IRX-JAVA-2 (Oniguruma rejects quantified bare anchors outright). Rechecked 2026-10-12 on Ruby 4.0.7 and Oniguruma 6.9.10; the Ruby forms are the shape of Ruby #22418. Oniguruma's GitHub repo is archived (April 2025), so there is no tracker for the Oniguruma half |
| IRX-ONIG-2 | Oniguruma | Open · not filed | wrong result (syntax compatibility): with `ONIG_SYNTAX_PYTHON`, `a*+a` matches `"a"`, `a++a` matches `"aa"`, `a?+a` matches `"a"` → expected no match (CPython 3.11+ reads `*+`, `++`, `?+` as possessive; CPython 3.14 gives no match for all three) | Tested: Oniguruma 6.9.10. The Python syntax accepts atomic groups `(?>…)`, added to Python in 3.11 together with possessive quantifiers, but parses `a*+` silently as a repeated `a*`. Found by the round-10 campaign on `onig-python`; the `onig-python` dialect no longer generates possessive quantifiers |
| IRX-PYRE-1 | Python `re` | Open · not filed | wrong result: `re.fullmatch(r"(?:a+){2}+", "aa")` → `None`; also `(?:a+){2,}+`, `(?:a+){2,3}+`, and `re.search` → expected a match `[0,2)` (Perl, PCRE2, `regex`; `(?>(?:a+){2})` matches in `re` itself) | Tested: CPython 3.11.13, 3.12.5, 3.13.16, 3.14.8. A possessive counted repeat (minimum ≥ 2) of a group whose body is itself a greedy loop: the earlier iteration does not give back characters inside the possessive repeat. `(?:a+){1,}+`, `(?:a*){2,}+`, `(?:ab?){2}+` are fine |
| IRX-PYREGEX-1 | Python `regex` module | Open · not filed | crash at compile: `regex.compile(r"\p{L}|\P{L}", regex.I)` → `AttributeError: 'AnyAll' object has no attribute 'rebuild'`; also `\p{C}|\P{C}`, `a|\p{L}|\P{L}` → expected a pattern matching any character | Tested: `regex` 2026.9.29 on CPython 3.14.8. An alternation of a property and its complement under IGNORECASE; without `I`, or as a class `[\p{L}\P{L}]`, it compiles |
| IRX-RUBY-1 | Ruby | Open · [#22429](https://bugs.ruby-lang.org/issues/22429) | wrong result: `/\A(?:a(?:()\|a){3,}){2}\z/.match?("aa")` → `false`; `/\A(?:(?:()\|()){3,}a){0,3}\z/.match?("aaa")` → `false` → expected `true` | Tested: Ruby 4.0.7 (Onigmo). an empty **capture** as a branch of a `{3,}` loop inside a counted group. The same patterns with `(?:)` instead of `()` match, as does `{2,}`; Oniguruma 6.9.10 is correct. Found by the new empty-atom spellings. Simpler: `/\A(?:(){1,2}?a)+\z/.match?("aa")` → `false` (true with `(?:)`, with a greedy `{1,2}`, or on `"a"`) |
| IRX-RE2-1 | RE2 | Open · [#676](https://github.com/google/re2/issues/676) | wrong result: `RE2::FullMatch("ſ", "a\|[sS]")` → `true`; `b\|[kK]` matches `"K"` (U+212A) → expected `false` | Tested: RE2 2025-11-05 (Homebrew; C++). no `i` flag: merging the alternatives into one class appears to add the case-fold partners of `s`/`k` (U+017F, U+212A). `[sS]` alone and `a\|s\|S` are correct (likewise `[kK]`, `b\|k\|K`); Go's `regexp` is correct |
| IRX-RE2-2 | RE2 | Open · [#677](https://github.com/google/re2/issues/677) | wrong span (mid-character): `RE2("\\B").Match("aé", 0, 3, UNANCHORED, &m, 1)` → `[2,2)`, between the two bytes of `é`; same for `Σ` → expected `[3,3)` (end of string) | Tested: RE2 2025-11-05 (Homebrew; C++). `\B` treats the bytes of a multi-byte UTF-8 character as non-word characters, so an empty match can start inside one. Go's `regexp` is correct. Found by span mode |
| IRX-RE2-3 | RE2 | Open · not filed | wrong span: `RE2("()(?:(|a)*?)*")` on `"a"` → match `[0,1)` (group 2 `[0,1)`); also `[0,2)` on `"aa"`, and `(b?)(?:(|a)*?)*`, `()(?:(a|)*?)*` → expected `[0,0)` (leftmost-first: the lazy inner loop takes zero iterations, so the outer loop's first iteration is empty and ends it; Go, re2j, Rust `regex`, regex-automata and PCRE2 all give `[0,0)`) | Tested: RE2 2025-11-05 (latest release; `master` has no matching changes). Needs a capture group before the loop: `(?:)(?:(|a)*?)*` gives `[0,0)`. Also with only the whole match requested. Found by the new cross-engine check (`tools/irx_diff.py`): 10 of 50,000 cases, all RE2 against the other six automata engines |
| IRX-RE2J-1 | re2j | Open · not filed | wrong result: `Pattern.compile("\\p{Ll}", CASE_INSENSITIVE).matcher("A").matches()` → `false`; also `B`…`Z` → expected `true` (the same pattern matches `"Σ"`, and `(?i)\p{Lu}` matches `"a"`; C++ RE2 matches `A`) | Tested: re2j 1.8 (Maven Central). Case-insensitive `\p{Ll}` leaves out ASCII uppercase while it folds every other cased letter in. Separately, re2j's Unicode tables are old (U+180E is still `Zs`, U+1F600 has no category). Found by the new `re2j` target's self-check. |
| IRX-RESHARP-1 | RE# | Partly resolved in 0.7.6 · [#33](https://github.com/ieviev/resharp/issues/33) | wrong result: `\A(?:a(?=b)?(?:bc)?)\z` matches `"ab"`; also `\A(?:a(?:c\|(?=b))(?:c\|(?=b)))\z` → expected no match | Tested: RE# (`resharp` 0.7.5, Rust). still reproduces on upstream main `28a7446de29f` (2026-09-17); an optional or alternated lookahead followed by more pattern accepts a character nothing consumes; `a(?=b)(?:bc)?` (lookahead not optional) is correct **Rechecked 2026-10-15 on RE# 0.7.6: `\A(?:a(?=b)?(?:bc)?)\z` no longer matches `"ab"`; `\A(?:a(?:c\|(?=b))(?:c\|(?=b)))\z` still does.** |
| IRX-EMACS-1 | Emacs | Open · not filed | crash (SIGABRT): `emacs -Q --batch -l hosts/emacs/host.el shell < docs/repros/IRX-EMACS-1.jsonl` → `abort()` in `forall_firstchar_1` ← `regex_compile` ← `string_match_1`, while compiling the translation of `[aσ]\|(?:-\|\B)[😀İ](?:)(?:[a-c]\|^)\|(?:\b)?\|(?:\w*?)*\|$` → expected compiles | Tested: GNU Emacs 31.1 (Homebrew, native-comp). deterministic with the recorded 10-pattern batch (each pattern is needed). Compiling that pattern alone, or replaying the same `string-match` calls without the host's JSON work, does not abort, so it looks like stale or uninitialized state in the compiler (8 batches in 10 minutes) |
| IRX-EMACS-2 | Emacs | Open · not filed | wrong span: `(string-match "\\(?:^\\(?:a*\\)*\\)\\{2\\}" "a")` → `(match-end 0)` = 0; also `\(?:\(?:[^z]\|\)\{0,3\}\b\)\{2\}` on `"\naaa"` → `(0 1)` → expected 1; `(0 4)` (the equivalent `\(?:^a*\)\{2\}` and `\(?:[^z]\{0,3\}\b\)\{2\}` give these) | Tested: GNU Emacs 31.1. A loop whose body can match empty, nested in a repeated group: the second outer iteration takes the empty path instead of the greedy one, so the match is shorter than Emacs's own backtracking order gives. Anchored (full) matches succeed. Found in span/capture mode by the 30-minute campaign |
| IRX-HS-1 | Vectorscan | Open · not filed | wrong result (length-dependent): `hs_compile("\\A.*\\s\\z", HS_FLAG_UTF8 | HS_FLAG_UCP, …)` matches `"a"×15 + " "` (16 bytes) but not `"a"×16 + " "` (17 bytes) → expected a match at every length | Tested: Vectorscan 5.4.13 (Homebrew), block mode, standalone C. Fails once the text before the final whitespace reaches 16 bytes, whatever the characters (16 ASCII, 8 two-byte, 6 three-byte, 4 four-byte); without `HS_FLAG_UCP`, with `^…$`, and with `.*[ ]` or `\S*\s` it is correct, and `.*\s\z` unanchored fails at 17 bytes but matches at 41. Found by the long-input campaign (`.*\s` on `"ß"×8 + " "`) |
### Imported from regex_comparison

<!-- regex engine bugs: 43, structural: 15 -->
| ID | Engine | Status / report | Repro / behavior | Notes |
|---|---|---|---|---|
| [JSC-1](../regex_comparison/bugs/BUGS.md#jsc-1) | JavaScriptCore | Resolved · not filed | wrong result: `/u` mixed ASCII/astral class misses an astral character after index 0 | Tested: JavaScriptCore (Bun); latest Bun 1.4.2. `/u` class with an ASCII range + astral range misses astral chars after index 0 |
| [JSC-2](../regex_comparison/bugs/BUGS.md#jsc-2) | JavaScriptCore | Resolved · not filed | wrong result: `(?:^)?` or `(?:^)*` misses a match after index 0 | Tested: JavaScriptCore (Bun); latest Bun 1.4.2. `(?:^)?` / `(?:^)*` makes the match fail when it doesn't start at index 0 |
| IRX-JSC-3 | JavaScriptCore | Open · not filed | wrong result: `/^\p{Ll}$/ui.test("S")` → `false`; also `/^\p{Lu}$/ui.test("s")`, the same under `vi` → expected `true` (case-insensitive property matching; V8, QuickJS) | Tested: system JavaScriptCore on macOS 27.0 (bundle 22625.1.29.11.27). Bun 1.4.2's JavaScriptCore matches, so this may be specific to the system build; not yet checked against WebKit trunk. Found while checking the `\q{}` results |
| IRX-JSC-4 | JavaScriptCore | Open · not filed | wrong result: `/^[^[^a]k]$/v.test("a")` → `false`; also `/^a[^[^a]k]$/v` on `"aa"`; conversely `/^[^[^a][^b]]$/v.test("a")` → `true` → expected `true`, `true`, `false` (a complemented class that contains a complemented class and other members; V8, Bun's JavaScriptCore) | Tested: system JavaScriptCore on macOS 27.0. Bun 1.4.2's JavaScriptCore is right, like IRX-JSC-3, so the system build may predate a fix. Found by the round-10 campaign on `jsc` |
| [JAVA-1](../regex_comparison/bugs/BUGS.md#java-1) | Java | Open · not filed | wrong result: lookbehind misses an escaped supplementary code point | Tested: java.util.regex; latest OpenJDK 27. lookbehind never matches an *escaped* supplementary code point |
| [PERL-1](../regex_comparison/bugs/BUGS.md#perl-1) | Perl | Resolved in blead 5b2f72d · [#24915](https://github.com/Perl/perl5/issues/24915) | wrong result: `/x+(?:b{2}){2}/` misses `"xxbbbb"` | Tested: Perl; latest 5.44.0. `(?:b{2}){2}` after any `+`/`*` quantifier fails: `/x+(?:b{2}){2}/` misses `"xxbbbb"` **Rechecked 2026-10-15: resolved in Perl blead 5.45.4 (`5b2f72d`); still fails in 5.44.0.** |
| [DOTNET-1](../regex_comparison/bugs/BUGS.md#dotnet-1) | .NET | Resolved · [#135328](https://github.com/dotnet/runtime/issues/135328) | hang: `(?:\|a?\|b)+?c` never returns on `"a"` | Tested: .NET Regex (interpreter); latest .NET 11.0.0-rc.1. `(?:\|a?\|b)+?c` on `"a"` never terminates (the two-branch form was fixed in .NET 10). Still affected in .NET 10.0.12; fixed in .NET 11 RC 1. |
| [SWIFT-1](../regex_comparison/bugs/BUGS.md#swift-1) | Swift Regex | Open · [#750](https://github.com/swiftlang/swift-experimental-string-processing/issues/750) | rejects valid pattern: `try Regex(#"[\x{2000}-\x{200a}]"#)` throws | Tested: Swift Regex; latest Swift 6.4. range endpoints that aren't NFC-stable are rejected |
| [SWIFT-2](../regex_comparison/bugs/BUGS.md#swift-2) | Swift Regex | Open · [#902](https://github.com/swiftlang/swift-experimental-string-processing/issues/902) | wrong capture: `/(a){0}(b)/` on `"ab"` reports `""`; expected `nil` | Tested: Swift Regex; latest Swift 6.4.0. a group quantified `{0}` (never run) reports an empty capture instead of nil: `"ab".firstMatch(of: /(a){0}(b)/)!.1` is `""` at 1 |
| [SWIFT-PERF-1](../regex_comparison/bugs/BUGS.md#swift-perf-1) | Swift Regex | Open · [#894](https://github.com/swiftlang/swift-experimental-string-processing/issues/894) | hang: `(?:.b\|)+.` never returns on `"a"` or `""` | Tested: Swift Regex; latest Swift 6.4. `(?:.b\|)+.` never returns, even on `"a"` or `""` (minimized 2026-10-07; originally seen as a >5 min match) |
| [NIM-1](../regex_comparison/bugs/BUGS.md#nim-1) | nim-regex | Resolved in 0.27.0 · [#169](https://github.com/nitely/nim-regex/issues/169), [#170](https://github.com/nitely/nim-regex/issues/170) | crash: `{m,n}` around lookaround raises `AssertionDefect` | Tested: nim-regex; latest 0.26.3. `{m,n}` around a lookaround aborts the compiler with an `AssertionDefect`; inside an optional group it compiles and silently misses matches **Rechecked 2026-10-15: resolved in nim-regex 0.27.0 (fails in 0.26.3).** |
| [NIM-3](../regex_comparison/bugs/BUGS.md#nim-3) | nim-regex | Resolved in 0.27.0 · [#166](https://github.com/nitely/nim-regex/issues/166) | segfault: `re2("a?(?:b?)*c")` crashes while compiling | Tested: nim-regex; latest 0.26.3. `re2("a?(?:b?)*c")` crashes the process (SIGSEGV) while compiling **Rechecked 2026-10-15: resolved in nim-regex 0.27.0 (fails in 0.26.3).** |
| [NIM-4](../regex_comparison/bugs/BUGS.md#nim-4) | nim-regex | Resolved in 0.27.0 · [#167](https://github.com/nitely/nim-regex/issues/167) | slow compile: `re2("(?:\|y\|()){22}")` takes about 12 s | Tested: nim-regex; latest 0.26.3. `re2("(?:\|y\|()){22}")` takes ~12 s to compile, and each +1 on the count costs ×2.4 **Rechecked 2026-10-15: resolved in nim-regex 0.27.0 (fails in 0.26.3).** |
| [PERL-3](../regex_comparison/bugs/BUGS.md#perl-3) | Perl | Resolved · [#24926](https://github.com/Perl/perl5/issues/24926) | wrong span: `"aaaa" =~ /(?:x??\x{100})*a+/` matches only `"a"` | Tested: Perl; latest 5.44.0. `"aaaa" =~ /(?:x??\x{100})*a+/` matches `"a"`: a greedy quantifier after a starred group with a lazy optional and a char above U+00FF matches as few times as possible. Fixed by [perl5#24930](https://github.com/Perl/perl5/pull/24930), merged as `b27da40`; rebuilt blead `06de9ae` returns `"aaaa"` |
| [PERL-2](../regex_comparison/bugs/BUGS.md#perl-2) | Perl | Resolved in blead 5b2f72d · [#24916](https://github.com/Perl/perl5/issues/24916) | wrong result: `"àéàj" =~ /à+j/` misses a match | Tested: Perl; latest 5.44.0. `"àéàj" =~ /à+j/` misses: Latin-1 char repeated with `+` on a UTF-8 string, when another Latin-1 char sits between runs **Rechecked 2026-10-15: resolved in Perl blead 5.45.4 (`5b2f72d`); still fails in 5.44.0.** |
| [EMACS-1](../regex_comparison/bugs/BUGS.md#emacs-1) | Emacs | Open · not filed | wrong result: `(rx (? bos) "a")` matches `"?a"` but misses `"a"` | Tested: Emacs `rx`; latest Emacs 31.1. `(rx (? bos) "a")` is `` "\\`?a" ``, where Emacs reads the `?` as a literal: it matches `"?a"` but not `"a"`. `rx` brackets `bol` but not `bos` |
| [RACKET-1](../regex_comparison/bugs/BUGS.md#racket-1) | Racket | Open · [#5603](https://github.com/racket/racket/issues/5603) | wrong result: `#px"[І-Ӱ]"` misses `"э"` | Tested: Racket regexps (`#rx`/`#px`); latest Racket 9.3. character ranges lose part of their middle: `#px"[І-Ӱ]"` (U+0406–U+04F0) doesn't match `"э"` (U+044D); about 5% of random ranges are affected |
| [RACKET-2](../regex_comparison/bugs/BUGS.md#racket-2) | Racket | Open · [#5604](https://github.com/racket/racket/issues/5604) | wrong result: `#px"(?<!.)x"` matches `"éx"` | Tested: Racket regexps (`#px`); latest Racket 9.3. a negative lookbehind that can match characters of different UTF-8 lengths succeeds wrongly: `#px"(?<!.)x"` and `#px"(?<![aé])x"` match `"éx"` |
| [RACKET-3](../regex_comparison/bugs/BUGS.md#racket-3) | Racket | Open · [#5606](https://github.com/racket/racket/issues/5606) | invalid span: `#px"(?!é)(?!$)"` matches inside `"éé"` | Tested: Racket regexps (`#px`/`#rx`); latest Racket 9.3. a match made only of zero-width assertions can start inside a multi-byte char: `(regexp-match? #px"(?!é)(?!$)" "éé")` is `#t`; on a port the match is at byte 1, mid-`é` |
| [RHOMBUS-1](../regex_comparison/bugs/BUGS.md#rhombus-1) | Rhombus | Open · not filed | wrong result: `rx'["]" "a"]'` loses `]` from its charset | Tested: Rhombus `rx`; latest rhombus-lib (Racket 9.3). a `]` in a charset, alone or inside a range, is never matched: `rx'["]" "a"]'` compiles to `#px"^[[a]$"`, `rx'["["-"^"]'` to `#px"^[[\\[^]$"` |
| [RHOMBUS-2](../regex_comparison/bugs/BUGS.md#rhombus-2) | Rhombus | Open · not filed | wrong result: a range crossing surrogates misses U+E000–U+FFFF | Tested: Rhombus `rx`; latest rhombus-lib (Racket 9.3). charsets with a range spanning the surrogates lose U+E000–U+FFFF: `rx'["?"-"\U0010FFFF"]'`, `rx'[! "a"]'` and a 797-range `\W` class don't match `"\uFFFD"`/`"﷏"` |
| [RHOMBUS-3](../regex_comparison/bugs/BUGS.md#rhombus-3) | Rhombus | Open · not filed | wrong result: an all-empty alternation lets `"C"` match where `"bC"` is required | Tested: Rhombus `rx`; latest rhombus-lib (Racket 9.3). an alternation whose branches are all empty loses its group: `rx'"b" ("" \|\| "") "C"'` compiles to `#px"^(?:(?:b\|)C)$"` and matches `"C"` |
| [NIM-6](../regex_comparison/bugs/BUGS.md#nim-6) | nim-regex | Open · [#180](https://github.com/nitely/nim-regex/issues/180) | wrong result: `"xa".find(re2"xa{0}")` matches `"xa"`; expected `"x"` | Tested: nim-regex; latest 0.27.0. `{0}` acts as `{1}`: `"xa".find(re2"xa{0}")` matches `"xa"`, `^(a){0}$` misses `""`, `(a){0}b` misses `"b"` |
| [NIM-7](../regex_comparison/bugs/BUGS.md#nim-7) | nim-regex | Open · [#181](https://github.com/nitely/nim-regex/issues/181) | wrong capture: `a(@.+?,){0,5}?7` captures `"@x,@y,"`; expected `"@y,"` | Tested: nim-regex; latest 0.27.0. in a lazy bounded loop `{m,n}?`, one long iteration beats two short ones: `"a@x,@y,7".find(re2"a(@.+?,){0,5}?7")` gives group 1 = `"@x,@y,"`, expected `"@y,"` |
| [NIM-5](../regex_comparison/bugs/BUGS.md#nim-5) | nim-regex | Resolved · not filed | wrong span in 0.26.3: `"ab".find(re2"a??b")` starts at 1; expected 0 | Tested: nim-regex; latest main `b0b76981aedb`. `"ab".find(re2"a??b")` reports a match starting at 1, not the leftmost 0: a lazy or empty-first choice at the start makes `find` prefer a later start. `contains` is correct. Passes on upstream main `b0b76981aedb` (unreleased). |
| [NIM-2](../regex_comparison/bugs/BUGS.md#nim-2) | nim-regex | Resolved in 0.27.0 · [#168](https://github.com/nitely/nim-regex/issues/168) | wrong result: `(?<=a)aa` misses `"aaa"` | Tested: nim-regex; latest 0.26.3. `(?<=a)aa` misses `"aaa"`: after a lookbehind rejects one occurrence of a literal, overlapping occurrences are skipped **Rechecked 2026-10-15: resolved in nim-regex 0.27.0 (fails in 0.26.3).** |
| [DOTNET-4](../regex_comparison/bugs/BUGS.md#dotnet-4) | .NET | Open · [#135329](https://github.com/dotnet/runtime/issues/135329) | wrong result: `(?:a+\|){5}` misses `"aaaa"` | Tested: .NET Regex (all 3 engines); latest .NET 11.0.0-rc.1. `(?:a+\|){5}` doesn't match `"aaaa"` (it can match `""`!); `(?:a+\|){2}d` misses `"ad"`. Interpreter, Compiled and NonBacktracking all wrong. Still affected in .NET 11 RC 1. |
| [JAVA-3](../regex_comparison/bugs/BUGS.md#java-3) | Java | Open · not filed | invalid span: `find()` reports a match at UTF-16 index 2 inside `"a😀b"` | Tested: java.util.regex; latest OpenJDK 27. iterating `find()` over `"a😀b"` with an empty-matching pattern reports an empty match at UTF-16 index 2, *inside* the emoji's surrogate pair |
| [JAVA-4](../regex_comparison/bugs/BUGS.md#java-4) | Java | Open · [JDK-8187080](https://bugs.openjdk.org/browse/JDK-8187080) | wrong capture: `(?:(.))+\d` on `"ab5"` captures `"5"`; expected `"b"` | Tested: java.util.regex; latest OpenJDK 27. `(?:(.))+\d` on `"ab5"` gives group 1 = `"5"`, a value from a loop iteration that backtracking undid; expected `"b"` |
| [JAVA-2](../regex_comparison/bugs/BUGS.md#java-2) | Java | Open · not filed | wrong result: `(?:u\|\b){3}d` misses `"uud"` | Tested: java.util.regex; latest OpenJDK 27. `(?:u\|\b){3}d` misses `"uud"`: a zero-width iteration can't count toward a loop minimum |
| [RUBY-1](../regex_comparison/bugs/BUGS.md#ruby-1) | Ruby | Open · [#22418](https://bugs.ruby-lang.org/issues/22418) | wrong result: `(?:u\|\b){3}d` misses `"uud"` | Tested: Onigmo (Ruby); latest Ruby 4.0.7. same as JAVA-2: `(?:u\|\b){3}d` misses `"uud"` |
| [RUBY-2](../regex_comparison/bugs/BUGS.md#ruby-2) | Ruby | Open · [#22418](https://bugs.ruby-lang.org/issues/22418) | wrong result: `(?:a(?:()\|b){1,3}){2}` misses `"aa"` | Tested: Onigmo (Ruby); latest Ruby 4.0.7. `(?:a(?:()\|b){1,3}){2}` misses `"aa"`: a `{m,n}` loop (n ≥ 3) over an empty capture group or `b`, inside an outer loop, won't take the empty branch again; `{1,2}` and a plain empty branch are right |
| [DOTNET-3](../regex_comparison/bugs/BUGS.md#dotnet-3) | .NET | Resolved · [#135330](https://github.com/dotnet/runtime/issues/135330) | wrong result: `(?:(?:\|,)(?:w\|)+?7){3}z` misses `"7,7,7z"` | Tested: .NET Regex (interpreter); latest .NET 11.0.0-rc.1. `(?:(?:\|,)(?:w\|)+?7){3}z` misses `"7,7,7z"`: exact repeat containing a lazy possibly-empty loop; Compiled is correct. Still affected in .NET 10.0.12; fixed in .NET 11 RC 1. |
| [DOTNET-5](../regex_comparison/bugs/BUGS.md#dotnet-5) | .NET | Resolved · [#135331](https://github.com/dotnet/runtime/issues/135331) | invalid span: `(?:(?:a\|)+?b){2}` on `"ab"` reports Index 2, Length 1 | Tested: .NET Regex (interpreter); latest .NET 11.0.0-rc.1. `(?:(?:a\|)+?b){2}` "matches" `"ab"` at Index=2, Length=1 (past the end of the string); `.Value` throws, `Replace` crashes. Still affected in .NET 10.0.12; fixed in .NET 11 RC 1. |
| [V8-1](../regex_comparison/bugs/BUGS.md#v8-1) | V8 | Partly resolved · [#572154295](https://issues.chromium.org/issues/572154295) | wrong result: `/[\u{10000}-\u{10FFFF}]$/u` misses `"\u{115D3}"` | Tested: V8 (Node, Deno); latest Chrome 155.0.8059.40, Node 26.11.0, Deno 2.9.7. `/[^a]$/u.test("😀")` is fixed in Chrome 155, but `/[\u{10000}-\u{10FFFF}]$/u.test("\u{115D3}")` still fails there. Node 26 reproduces both |
| [V8-3](../regex_comparison/bugs/BUGS.md#v8-3) | V8 | Open · [#571450188](https://issues.chromium.org/issues/571450188) | wrong result: `/[^]*?a^\|/.test("")` returns `false`; expected `true` | Tested: V8 (Node, Deno); latest Node 26.11.0, Deno 2.9.7. `/[\s\S]*?x^\|/.test("")` is false: a lazy match-anything class, a literal and `^` sink the whole regex. Node 25 is correct. Regression. |
| [V8-2](../regex_comparison/bugs/BUGS.md#v8-2) | V8 | Resolved · not filed | wrong result in older V8: `/u` or `/v` matches inside a surrogate pair | Tested: V8 (Node, Deno); latest Chrome 155.0.8059.40, Node 26.11.0, Deno 2.9.7. with `/u` or `/v`, V8 tried match positions inside surrogate pairs; all six recorded cases pass in Chrome 155. Resolved in Chrome 155; older V8 is still affected. |
| [ICU-1](../regex_comparison/bugs/BUGS.md#icu-1) | ICU | Open · not filed | wrong result: `(?:X*?)+?Y` misses `"XY"` | Tested: ICU (`NSRegularExpression`); latest macOS 27.0. `(?:X*?)+?Y` doesn't match `"XY"`: a lazy loop over a lazy, possibly-empty body gives up |
| [ICU-2](../regex_comparison/bugs/BUGS.md#icu-2) | ICU | Open · not filed | hang: `(?:a*)*?;b` never returns on `";c"` | Tested: ICU (`NSRegularExpression`); latest macOS 27.0. `(?:a*)*?;b` on `";c"` never terminates |
| [DOTNET-6](../regex_comparison/bugs/BUGS.md#dotnet-6) | .NET | Open · [#135584](https://github.com/dotnet/runtime/issues/135584) | wrong span: `Regex.Match("aaba", "(?:(?:ab??)+){2}")` returns `"aa"`; expected `"aaba"` | Tested: .NET Regex (all 3 engines); latest .NET 11.0.0-rc.1. `Regex.Match("aaba", "(?:(?:ab??)+){2}")` is `"aa"`; backtracking semantics (PCRE, Perl, Python, Java) and Rust/Go give `"aaba"`. A greedy loop nested in a counted loop, with a lazy optional at the end of the body |
| [DOTNET-2](../regex_comparison/bugs/BUGS.md#dotnet-2) | .NET | Resolved · [#135332](https://github.com/dotnet/runtime/issues/135332) | wrong result: a pattern with ≥256 distinct character sets misses matches | Tested: .NET Regex (NonBacktracking); latest .NET 11.0.0-rc.1. misses real matches once the pattern has ≥ 256 distinct character sets; 255 works. Still affected in .NET 10.0.12; fixed in .NET 11 RC 1. |
| [ICU-3](../regex_comparison/bugs/BUGS.md#icu-3) | ICU | Open · not filed | wrong result: `(?:(?:C*)+?x)?` returns `false` on `""`; expected `true` | Tested: ICU (`NSRegularExpression`); latest macOS 27.0. `(?:(?:C*)+?x)?` returns false on `""`: a failing lazy loop over a possibly-empty body at end of input aborts the whole match, skipping alternatives |
| [HS-1](../regex_comparison/bugs/BUGS.md#hs-1) | Hyperscan | Open · not filed | wrong result: `(?:[^é]+)+.c` matches `"aééc"` in UTF-8 mode | Tested: Hyperscan (Vectorscan); latest 5.4.13. with `HS_FLAG_UTF8`, `(?:[^é]+)+.c` matches `"aééc"`: a repeated group splits a multi-byte character |
| [RESHARP-1](../regex_comparison/bugs/BUGS.md#resharp-1) | RE# | Open · [#32](https://github.com/ieviev/resharp/issues/32) | wrong span: `\B` matches at byte 1 inside `"é"` | Tested: RE# (`resharp` crate); latest 0.7.5. zero-width matches are reported *inside* multi-byte UTF-8 characters: `\B` matches `"é"` (at byte 1), and so does `(?<!é)(?!é)` |
| [RUST-PERF-1](../regex_comparison/bugs/BUGS.md#rust-perf-1) | Rust regex | Documented · not filed | quadratic iteration: `(?:a(\w+[A-Z])y)\|.` takes about 4× longer when input doubles | Tested: Rust `regex::bytes::Regex::find_iter`; latest regex 1.13.1. `(?:a(\w+[A-Z])y)\|.` on long `a` runs takes ~4× longer when input doubles |

#### Structural matchers (CSS selectors, DOM, FileCheck, macros, ISel)

| ID | Engine | Status / report | Repro / behavior | Notes |
|---|---|---|---|---|
| [LOLHTML-1](../regex_comparison/bugs/BUGS.md#lolhtml-1) | lol-html | Open · [#341](https://github.com/cloudflare/lol-html/issues/341) | wrong CSS match: `[a^=""]` selects elements with nonempty `a` | Tested: lol-html (Bun `HTMLRewriter`); latest Bun 1.4.3 (fork of lol-html v2.7.2); matcher code unchanged in lol-html v3.0.1. `[a^=""]` and `[a$=""]` match every element whose `a` is non-empty, and `[a~=""]` matches `a=""` or values with leading, trailing or doubled spaces; by spec an empty value matches nothing (`[a*=""]` is right) |
| [SOUPSIEVE-1](../regex_comparison/bugs/BUGS.md#soupsieve-1) | soupsieve | Open · [#313](https://github.com/facelessuser/soupsieve/issues/313) | wrong CSS match: `* > r` selects the document root | Tested: soupsieve (Beautiful Soup); latest soupsieve 3.0.2, beautifulsoup4 4.15.0. the `BeautifulSoup` document object counts as an element: `* > *` and `* > r` match the root element |
| [LEXBOR-1](../regex_comparison/bugs/BUGS.md#lexbor-1) | Lexbor | Open · [#436](https://github.com/lexbor/lexbor/issues/436) | wrong CSS match: `div > :is(y) ~ *` finds only the next sibling | Tested: Lexbor (selectolax 1.0.0, bundling lexbor main `f4cbbcd`). after `:is()`/`:where()`/`:not()`, `~` acts like `+`: `div > :is(y) ~ *` finds only the next sibling (`div > y ~ *` is right) |
| [JSDOM-1](../regex_comparison/bugs/BUGS.md#jsdom-1) | jsdom | Open · [dom-selector #370](https://github.com/asamuzaK/domSelector/issues/370) | wrong CSS match: `[a\|=""]` misses `a=""` and `a="-x"` | Tested: jsdom (`@asamuzakjp/dom-selector`); latest jsdom 30.1.2, dom-selector 10.0.1. `[a\|=""]` matches nothing; browsers match `a=""` and `a="-x"` |
| [CSSSELECT-1](../regex_comparison/bugs/BUGS.md#cssselect-1) | css-select | Open · [#1910](https://github.com/fb55/css-select/issues/1910) | wrong CSS match: `[a~=""]` selects empty or irregularly spaced values | Tested: css-select (cheerio, linkedom); latest css-select 7.0.0. `[a~=""]` matches `a=""` and values with leading, trailing or doubled spaces, like LOLHTML-1 |
| [LINKEDOM-1](../regex_comparison/bugs/BUGS.md#linkedom-1) | linkedom | Open · [#342](https://github.com/WebReflection/linkedom/issues/342) | wrong DOM result: `getAttribute("class")` trims `" ab"` to `"ab"` | Tested: linkedom; latest 0.18.13. the class attribute is normalized: `getAttribute("class")` trims `" ab"` to `"ab"` and returns `""` when absent, so `[class=" "]` and `[class^=" a"]` miss |
| [HAPPYDOM-1](../regex_comparison/bugs/BUGS.md#happydom-1) | happy-dom | Open · [#2505](https://github.com/capricorn86/happy-dom/issues/2505) | wrong CSS match: `a ~ b` finds only the first later `b` | Tested: happy-dom; latest 21.0.1 (Chromium 156, Firefox 158, WebKit 27.2 agree with the spec). `a ~ b` finds only the first matching later sibling; `a ~ * ~ *` finds nothing |
| [HAPPYDOM-2](../regex_comparison/bugs/BUGS.md#happydom-2) | happy-dom | Open · [#2506](https://github.com/capricorn86/happy-dom/issues/2506) | wrong CSS match: `[a^=""]` selects `a=""` | Tested: happy-dom; latest 21.0.1 (Chromium 156, Firefox 158, WebKit 27.2 agree with the spec). `[a^=""]`, `[a$=""]`, `[a~=""]` match `a=""`; `[a\|=""]` misses `a="-x"` |
| [HAPPYDOM-3](../regex_comparison/bugs/BUGS.md#happydom-3) | happy-dom | Open · [#2507](https://github.com/capricorn86/happy-dom/issues/2507) | wrong CSS match: `r > :not(c):first-child:nth-child(2)` selects child 2 | Tested: happy-dom; latest 21.0.1 (Chromium 156, Firefox 158, WebKit 27.2 agree with the spec). a plain pseudo-class between two functional ones is dropped: `r > :not(c):first-child:nth-child(2)` and `r > :nth-child(2):first-child:not(c)` match the 2nd child |
| [HAPPYDOM-4](../regex_comparison/bugs/BUGS.md#happydom-4) | happy-dom | Open · [#2508](https://github.com/capricorn86/happy-dom/issues/2508) | wrong CSS match: `[p~="a b"]` selects `p="a b"` | Tested: happy-dom; latest 21.0.1 (Chromium 156, Firefox 158, WebKit 27.2 agree with the spec). `[p~="a b"]` matches `p="a b"`; a `~=` value containing whitespace must match nothing |
| [LLVM-GISEL-1](../regex_comparison/bugs/BUGS.md#llvm-gisel-1) | LLVM | Open · not filed | compile failure: `zext <4 x i13> %x to <4 x i128>` then `extractelement` | Tested: LLVM AArch64 GlobalISel; latest 23.1.2. `zext <4 x i13> %x to <4 x i128>` then `extractelement`: "cannot select: G_MERGE_VALUES gpr(i16) ×4 → gpr64"; by default it silently falls back to SelectionDAG |
| [CHIBI-1](../regex_comparison/bugs/BUGS.md#chibi-1) | Chibi | Open · [#1207](https://github.com/ashinn/chibi-scheme/issues/1207) | wrong macro match: `(_ b ...)` accepts `(m c)` with `b` declared literal | Tested: Chibi Scheme `syntax-rules`; latest chibi 0.12. a literal under `...` isn't checked: with literal `b`, `(_ b ...)` matches `(m c)` and `(m b (c))` |
| [PYFILECHECK-1](../regex_comparison/bugs/BUGS.md#pyfilecheck-1) | filecheck | Open · not filed | wrong result: `CHECK-NEXT: a` passes on `xbbba\na` after `CHECK: bbb` | Tested: filecheck (Python FileCheck clone); latest 1.0.6. `CHECK-NEXT` skips the rest of the previous match's line: `CHECK: bbb` / `CHECK-NEXT: a` passes on `xbbba\na`; LLVM fails it |
| [PYFILECHECK-2](../regex_comparison/bugs/BUGS.md#pyfilecheck-2) | filecheck | Open · not filed | wrong result: `CHECK-NOT: cb` fails on `cbx` before `CHECK: bx` | Tested: filecheck (Python FileCheck clone); latest 1.0.6. `CHECK-NOT` matches that overlap the next match count: `CHECK-NOT: cb` / `CHECK: bx` fails on `cbx`; LLVM passes. Likely the cause of upstream #10 |
| [SOUPSIEVE-2](../regex_comparison/bugs/BUGS.md#soupsieve-2) | soupsieve | Open · [#314](https://github.com/facelessuser/soupsieve/issues/314) | wrong CSS match: `div > :has(~ b)` selects `a` and `c`; expected only `a` | Tested: soupsieve (Beautiful Soup); latest soupsieve 3.0.2, beautifulsoup4 4.15.0. `:has(~ X)` is wrong: on `<a/><b/><c/>`, `div > :has(~ b)` selects a and c (Chrome: a) |

## Targets

Every regex engine from `../regex_comparison` has a directory `targets/<name>/` (engine command, dialect,
config overlay, campaign results and triage notes) and has run 1-, 5- and 10-minute campaigns
(`tools/irx_target.py`). A host speaks the line protocol (`driver.js`, `driver.pl`, `tools/bridge.py` or a
program under `hosts/`). The **model** column names the dialect that supplies the expected answers; every
target has its own. Structural matchers (CSS, DOM, FileCheck, macros, ISel) are out of scope.

| Target | Directory | Host | Model | Status |
|---|---|---|---|---|
| V8 15.5 (d8) | [`v8`](targets/v8) | `driver.js` | ES2024 (exact) | IRX-V8-1…5 |
| V8 linear engine; no-optimization and fallback paths | [`v8-linear`](targets/v8-linear), [`v8-noopt`](targets/v8-noopt) | d8 modes `linear`; `noopt`, `nopeephole`, `fallback0` | `es` (exact; linear: `""` and `s` flags only) | sweeps clean (706k / 250k per mode) |
| SpiderMonkey 158 (jsvu) | [`spidermonkey`](targets/spidermonkey) | `driver.js` (`sm`) | `es` (exact) | new |
| JavaScriptCore (system `jsc`) | [`jsc`](targets/jsc) | `driver.js` (`jsc`) | `es` (exact) | new |
| GraalJS 25.4 (TRegex) | [`graaljs`](targets/graaljs) | `driver.js` (`vendor/graaljs`) | `es` (exact) | IRX-GRAAL-1…3 |
| C++ `std::regex` (libc++) | [`cpp-regex`](targets/cpp-regex) | `hosts/c/cpp_regex_host` (`std::wregex`, ECMAScript) | `cpp`: ES subset, ASCII pool, `i`/`m` only | IRX-LIBCXX-1…5 |
| QuickJS (upstream `9d01a96`) | [`quickjs`](targets/quickjs) | `driver.js` (std) | ES2024 | IRX-QJS-1, IRX-QJS-2 |
| XS | [`xs`](targets/xs) | bridge | ES2024 | IRX-XS-1…11 |
| Boa | [`boa`](targets/boa) | bridge | ES2024 | IRX-BOA-1…8 |
| engine262 | [`engine262`](targets/engine262) | bridge | ES2024 | IRX-E262-1…5 |
| Hermes | [`hermes`](targets/hermes) | bridge | ES2024 minus `v` | IRX-HERMES-1…4 |
| JavaScriptCore (Bun 1.4.2) | [`bun`](targets/bun) | `driver.js` (node adapter) | ES2024 | clean (0 self-check mismatches) |
| V8 14.1 / 15.0 (Node, Deno) | [`node`](targets/node), [`deno`](targets/deno) | `driver.js` | ES2024 | older V8; excluded from the ledger and from `--all` campaigns (`campaign = false`) |
| Perl 5.44 / blead | [`perl`](targets/perl) | `driver.pl` | Perl `/u` (exact) | IRX-PERL-1…8 |
| Perl 5.44 `/a`, `/aa` | [`perl-a`](targets/perl-a), [`perl-aa`](targets/perl-aa) | `driver.pl` (`IRX_PERL_CHARSET`) | `perl-a`: ASCII classes; `perl-aa`: also no ASCII/non-ASCII case match (exact) | self-check: only IRX-PERL-6/7 |
| PCRE2 10.49 | [`pcre2`](targets/pcre2) | `hosts/c/pcre2_host` | `pcre2`: Perl with UCP `\w`/`\s` (exact) | IRX-PCRE2-1, 3 (JIT), IRX-PCRE2-2, 4…7 |
| PCRE2 10.49 JIT | [`pcre2-jit`](targets/pcre2-jit) | `hosts/c/pcre2_host` (`IRX_PCRE2_JIT=1`) | `pcre2` (exact) | 0 self-check mismatches; IRX-PCRE2-4 in the sweep |
| PCRE2 10.49 without UCP | [`pcre2-ascii`](targets/pcre2-ascii) | `hosts/c/pcre2_host` (`IRX_PCRE2_NOUCP=1`) | `pcre2-ascii`: ASCII classes, Unicode case folding (exact) | 0 self-check mismatches |
| Boost.Regex 1.92 | [`boost-regex`](targets/boost-regex) | `hosts/c/boost_regex_host` (`boost::wregex`, Perl syntax) | `boost`: ASCII classes and folding, fixed lookbehind, no quantified assertions | IRX-BOOST-1…5 |
| Erlang `re` (OTP 29) | [`erlang-re`](targets/erlang-re) | `hosts/erlang/host.escript` | `pcre2` (exact) | new |
| PCRE1 8.45 (interpreter, JIT) | [`pcre1`](targets/pcre1), [`pcre1-jit`](targets/pcre1-jit) | `hosts/c/pcre1_host` | `pcre1`: older UCP `\w`, fixed-length lookbehind | new |
| Sanitized engines (ASan/UBSan; Rust crates ASan only) | [`pcre2-asan`](targets/pcre2-asan), [`pcre2-jit-asan`](targets/pcre2-jit-asan), [`onig-asan`](targets/onig-asan), [`boost-asan`](targets/boost-asan), [`cpp-asan`](targets/cpp-asan), [`pcre1-asan`](targets/pcre1-asan), [`re2-asan`](targets/re2-asan), [`gnu-regex-asan`](targets/gnu-regex-asan), [`minrx-asan`](targets/minrx-asan), [`llvm-regex-asan`](targets/llvm-regex-asan), [`nim-regex-asan`](targets/nim-regex-asan), [`quickjs-asan`](targets/quickjs-asan), [`icu-c-asan`](targets/icu-c-asan), [`vectorscan-asan`](targets/vectorscan-asan), [`rust-regex-asan`](targets/rust-regex-asan), [`regex-lite-asan`](targets/regex-lite-asan), [`ra-pikevm-asan`](targets/ra-pikevm-asan), [`ra-backtrack-asan`](targets/ra-backtrack-asan), [`fancy-regex-asan`](targets/fancy-regex-asan), [`resharp-asan`](targets/resharp-asan) | `*_host_asan` (`tools/build_asan.sh`; RE2 with abseil, PCRE1, the gawk support library, LLVM's regex sources and QuickJS from source; Rust with nightly `-Zsanitizer=address`) | as the plain targets | no sanitizer reports in sweeps |
| Sanitized interpreters | [`python-re-asan`](targets/python-re-asan), [`python-regex-asan`](targets/python-regex-asan), [`perl-asan`](targets/perl-asan), [`ruby-onigmo-asan`](targets/ruby-onigmo-asan), [`tcl-asan`](targets/tcl-asan) | CPython 3.14 (also the `regex` module), Perl 5.44, Ruby 4.0, Tcl 9.1 built with sanitizers (`tools/build_asan_big.sh`, also ICU4C and Vectorscan) | as the plain targets | no sanitizer reports in sweeps |
| PHP 8.5 `preg_*` | [`php-pcre2`](targets/php-pcre2) | `hosts/script/php_host.php` | Perl (exact) | IRX-PCRE2-1…3 |
| Swift Regex 6.4 | [`swift-regex`](targets/swift-regex) | `hosts/swift` (scalar semantics) | Swift (exact) | IRX-SWIFT-1…7 |
| .NET 9 interpreter / Compiled / NonBacktracking | [`dotnet-interp`](targets/dotnet-interp), [`dotnet-compiled`](targets/dotnet-compiled), [`dotnet-nonbacktracking`](targets/dotnet-nonbacktracking) | `hosts/dotnet` | `dotnet` / `dotnet-nonbacktracking`: UTF-16 units, `\w` = L\|Mn\|Nd\|Pc (exact) | IRX-DOTNET-1…15 |
| .NET `RegexOptions.ECMAScript` | [`dotnet-ecma`](targets/dotnet-ecma) | `hosts/dotnet` (`ecma`) | `dotnet-ecma`: ECMA word class (with U+0130), `i`/`m` only | 0 self-check mismatches |
| ICU (`NSRegularExpression`) | [`icu`](targets/icu) | `hosts/swift` | `icu`: UTS #18 classes, Unicode line ends, CRLF `$` (exact) | IRX-ICU-1…7 |
| ICU4C 78 (uregex C API) | [`icu-c`](targets/icu-c) | `hosts/c/icu_host` | `icu` (exact), with offset and sticky | new |
| Rust `regex` | [`rust-regex`](targets/rust-regex) | `hosts/rust` | `rust` (exact) | 0 self-check mismatches; 1.2M patterns, 0 findings |
| Rust `regex-lite` 0.1 | [`regex-lite`](targets/regex-lite) | `hosts/rust` | `rust-lite`: ASCII classes and `(?i)`, no `\p` (exact) | IRX-RLITE-1 |
| regex-automata 0.4 engines | [`ra-pikevm`](targets/ra-pikevm), [`ra-backtrack`](targets/ra-backtrack), [`ra-onepass`](targets/ra-onepass), [`ra-hybrid`](targets/ra-hybrid), [`ra-dfa`](targets/ra-dfa) | `hosts/rust` (`automata_host`, `IRX_RA_ENGINE`) | `rust` (exact; unsupported patterns skipped) | PikeVM sweep clean |
| fancy-regex | [`fancy-regex`](targets/fancy-regex) | `hosts/rust` | `fancy`: fixed-length lookbehind, no empty-body quantifiers (exact) | IRX-FANCY-1 (fixed in 0.19.2), IRX-FANCY-2, 3 |
| RE# (`resharp`) | [`resharp`](targets/resharp) | `hosts/rust` | `resharp`: UnicodeMode::Full; no lazy, lookbehind, mid-pattern `^`/`\b`, lookahead under `*` (exact) | 0 self-check mismatches; named groups under quantifiers rejected; IRX-RESHARP-1 |
| RE2 | [`re2`](targets/re2) | `hosts/c/re2_host` | `re2`: ASCII classes (exact) | IRX-RE2-1, 2, 3 |
| RE2 `longest_match` | [`re2-longest`](targets/re2-longest) | `hosts/c/re2_host` (`IRX_RE2_LONGEST=1`) | `re2-longest`: leftmost-longest spans (exact; no captures) | 0 self-check mismatches |
| re2j 1.8 | [`re2j`](targets/re2j) | `hosts/java/Re2jHost.java` | `re2j`: RE2, old Unicode tables (U+180E, U+1F600 out of the pool) | IRX-RE2J-1 |
| Go `regexp` | [`go-regexp`](targets/go-regexp) | `hosts/go` | `go`: ASCII classes (exact) | 0 self-check mismatches |
| Go `regexp` `Longest` | [`go-longest`](targets/go-longest) | `hosts/go` (`IRX_GO_LONGEST=1`) | `go-longest`: leftmost-longest spans (exact; no captures) | 0 self-check mismatches |
| Oniguruma 6.9 | [`oniguruma`](targets/oniguruma) | `hosts/c/onig_host` | `oniguruma`: Unicode classes, Ruby anchors (exact) | IRX-ONIG-1 |
| Oniguruma Perl / Java / Python syntax, ASCII classes | [`onig-perl`](targets/onig-perl), [`onig-java`](targets/onig-java), [`onig-python`](targets/onig-python), [`onig-ascii`](targets/onig-ascii) | `hosts/c/onig_host` (`IRX_ONIG_SYNTAX`, `IRX_ONIG_ASCII`) | `onig-*`: single-line anchors, syntax spellings | 0 self-check mismatches |
| Ruby Onigmo | [`ruby-onigmo`](targets/ruby-onigmo) | `hosts/script/rb_host.rb` | `ruby`: ASCII `\w`, Unicode `\b`, always-on line anchors (exact) | IRX-ONIG-1, IRX-RUBY-1 |
| Python `re` | [`python-re`](targets/python-re) | `hosts/script/py_host.py` | `python`: isalnum `\w`, sre case groups, `(?P<…>)` (exact) | IRX-PYRE-1 |
| Python `regex` module | [`python-regex`](targets/python-regex) | `hosts/script/py_host.py` (`IRX_PY_ENGINE=regex`, `vendor/pyregex`) | `python-regex`: `\p{Word}` `\w`, `re` case groups, `\p`, variable lookbehind; ı and İ outside the pool (non-transitive case relation) | IRX-PYREGEX-1; self-check: only ı/İ probes |
| Java `java.util.regex` | [`java`](targets/java) | `hosts/java` | `java`: Java line ends, `lower(upper())` fold, range rule (exact) | IRX-JAVA-1…7 |
| Java without `UNICODE_CHARACTER_CLASS` | [`java-ascii`](targets/java-ascii) | `hosts/java` (`IRX_JAVA_ASCII=1`) | `java-ascii`: ASCII classes, `\b` with Java's non-spacing-mark rule (exact) | self-check: only IRX-JAVA-1 |
| nim-regex | [`nim-regex`](targets/nim-regex) | `hosts/nim` | `nim`: `(?P<…>)`, end-only `$`, case-mapped range endpoints (exact) | IRX-NIM-1, NIM-1, NIM-3, NIM-6 rediscovered |
| Tcl ARE | [`tcl`](targets/tcl) | `hosts/script/tcl_host.tcl` | `tcl`: `\y`, L\|Nd\|Pc words, `-linestop` negations, {p, upper, lower} nocase (exact) | IRX-TCL-1 |
| Racket `#px` | [`racket`](targets/racket) | `hosts/racket` | `racket`: ASCII classes, multi-mode `.`, asymmetric fold, `?`-only nullable quantifiers (exact) | IRX-RACKET-1…5; RACKET-1…3 rediscovered (RACKET-3 by span mode) |
| Emacs Lisp | [`emacs`](targets/emacs) | `hosts/emacs` (translator) | `emacs`: dumped syntax/script/case tables, edge and script-change `\b` (exact) | IRX-EMACS-1, IRX-EMACS-2 |
| Vectorscan (Hyperscan) | [`vectorscan`](targets/vectorscan) | `hosts/c/hs_host` | `vectorscan`: UCP classes, no anchors or `\b` (exact) | IRX-HS-1; ~70 ms per compile |
| LLVM `Regex` (POSIX ERE) | [`llvm-regex`](targets/llvm-regex) | `hosts/c/llvm_host` (translator) | `llvm`: ASCII-only model of a byte engine (exact) | IRX-LLVM-1, 2 |
| macOS libc regex (`regcomp`, TRE) | [`libc-regex`](targets/libc-regex) | `hosts/c/libc_regex_host` | `libc`: POSIX ERE, leftmost-longest, no `^`/`$` (exact) | IRX-LIBC-1, 2 |
| GNU regex (gawk 5.4's copy of the glibc code) | [`gnu-regex`](targets/gnu-regex) | `hosts/c/gnu_regex_host` (`tools/build_gawk_support.sh`) | `gnu`: POSIX ERE, no `^`/`$`, no `i` | new |
| MinRX (gawk 5.4) | [`minrx`](targets/minrx) | `hosts/c/minrx_host` | `llvm` (exact) | 1.1M-case sweep clean |
| Rhombus `rx`, Emacs `rx` | — | — | — | DSL front-ends: need a DSL printer, deferred |

<!-- END shared bug ledger -->

