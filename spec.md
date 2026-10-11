# Inverted-Pair Regex Fuzzer for d8 — Spec

Oct 9, 2026 · @Robert Morelli

> **Note (2026-10-11):** this is the original single-engine design, written for V8's `d8`. The implementation
> has since become a multi-engine fuzzer: per-engine dialect models (`src/dialects/`), 32 targets
> (`targets/`), protocol hosts (`hosts/`), and span and capture checks beyond full-match results. The core
> described here (span-relation pair grammar, sampling, harness, triage) is unchanged; see
> [`README.md`](README.md) for the current design and [`docs/phase2-captures.md`](docs/phase2-captures.md)
> for captures.

## Overview

The fuzzer picks an accept string A and a reject string R, then samples regexes that provably match A and provably reject R, and reports any case where V8 (via `d8`) disagrees. Each case has an independent model-derived oracle. A mismatch is a candidate bug in V8 or in the fuzzer's model, printer, or harness; triage establishes which. Independent engines are optional sanity checks, not the source of expected answers.

It targets semantic bugs (wrong match result, tier disagreement) that crash-only oracles do not detect. It runs on one machine, with concurrency selected from measured throughput and resource limits.

**Platform:** macOS on Apple Silicon (arm64) is the primary target. Nothing in the design may depend on Linux-only APIs. Linux support is a nice-to-have, not a requirement.

## Theory

For a fixed string w of length n, a subregex is abstracted by its span relation: the set of (i, j) with i ≤ j such that it matches w\[i..j\] in the context of the whole string w (assertions and lookarounds may look outside the span). This is an (n+1)×(n+1) boolean matrix, and the regex operators act on it exactly:

```latex
\mathrm{rel}(e_1 e_2) = \mathrm{rel}(e_1) \cdot \mathrm{rel}(e_2) \qquad \mathrm{rel}(e_1 | e_2) = \mathrm{rel}(e_1) \lor \mathrm{rel}(e_2) \qquad \mathrm{rel}(e^*) = I \lor \mathrm{rel}(e)^{+}
```

The abstract state of a subregex is the pair (rel\_A, rel\_R), one relation per string. Those pairs are the nonterminals of a finite grammar of regex syntax trees. A start nonterminal is any pair where (0, |A|) ∈ rel\_A and (0, |R|) ∉ rel\_R. Every tree derived from a start nonterminal is a regex that must fully match A and must not fully match R.

This is sound for JS backtracking semantics because, without backreferences, a full-match test explores every path, so the boolean result equals the set semantics. Lookarounds are atomic in JS, but with no captures observable, atomicity cannot change a boolean.

This is a regular tree language, so pairs, triples, or k strings compose by product with no intersection problem. For lengths a and r, the number of possible pairs is at most 2^(((a+1)(a+2) + (r+1)(r+2))/2), since each relation is upper triangular. Only reachable pairs are materialized, but the reachable set is not guaranteed to be small, so the table build is budgeted (see "Table build").

**Soundness vs. completeness.** Correctness of every case depends only on each materialized pair's relations being right. The table does not have to contain every reachable pair: any subgrammar we choose to materialize still yields only valid cases. This is what lets the build be capped without losing the oracle.

**Positions.** A string is a sequence of symbols. In non-`u`/`v` mode a symbol is a UTF-16 code unit, so an astral char is two positions (a surrogate pair). In `u`/`v` mode a symbol is a code point. Tables are therefore built per (A, R, flag set).

## Supported constructs

Version 1 covers the constructs listed below, including zero-width predicates encoded as diagonal relations. Backreferences are out of scope because they break this abstraction. Unicode property escapes (`\p`, `\P`), string-valued `v` classes (`\q` and properties of strings), and inline flag modifiers are not generated in v1. A property-escape example below is a diagnostic illustrating a mode difference, not an addition to the generation grammar.

| Construct | Relation effect | Notes |
| --- | --- | --- |
| Literal, `.`, class `[a-c]`, `[^x]`, `\d \w \s \D \W \S` | (i, i+1) where the symbol matches | Preserve class syntax; enumerated templates may use pool bits plus an "other" spelling bit, but evaluate full flag semantics |
| `v`-mode class set ops `[A--B]` `[A&&B]` nested classes | Same, set computed by the op | Only under `v` |
| Empty `(?:)` | Identity | Needed so ε is expressible |
| Concat, alternation | Matrix product, OR | Core of the grammar |
| `*` `+` `?` `{m,n}` `{m,}` `{m}` | Closure, bounded powers | `{m,n}` via repeated squaring; only m ≤ n emitted |
| Lazy `*?` `+?` `??` `{m,n}?` | Same relation as greedy | Full-match result is identical, so they are free mutations |
| `^` `$` `\b` `\B` | Diagonal (i, i) where the predicate holds | See flag semantics below |
| Lookahead `(?=e)` `(?!e)` | Diagonal: i where (i, j) ∈ rel(e) for some j (negated for `!`) | Body may extend to the end of w |
| Lookbehind `(?<=e)` `(?<!e)` | Diagonal: j where (i, j) ∈ rel(e) for some i (negated for `!`) | JS lookbehind matches right to left; same relation |
| Groups `( )` `(?: )` `(?<n> )` | Identity | Captures ignored by the boolean oracle; names must be unique per regex |
| Flags `i` `s` `m` `u` `v` | Change char sets and predicates | One atom table per flag set; `u` and `v` are mutually exclusive |

### Flag semantics the atom tables must model

These are the places where the model is most likely to be wrong, and also where V8 bugs are most likely. Each one gets an explicit unit test.

- **Line terminators** are LF, CR, U+2028, U+2029. `.` excludes them unless `s` is set. Under `m`, `^` holds at 0 or after a line terminator, and `$` holds at n or before one.
- **`\b` / `\B`**: `\b` holds at i iff IsWordChar(i−1) ≠ IsWordChar(i), where out-of-range positions are non-word. IsWordChar uses the same word set as `\w` under the current flags.
- **Case-insensitive, non-unicode (`i` without `u`/`v`)**: Canonicalize(c) = toUpperCase(c) if the result is a single code unit, else c; and a non-ASCII c never maps to an ASCII result.
- **Case-insensitive, unicode (`iu` / `iv`)**: Canonicalize uses simple case folding (CaseFolding.txt, statuses C and S). `\w` then also matches U+017F (ſ) and U+212A (Kelvin K), which also changes `\b`, `\B` and `\W`.
- **Case-insensitive matching under `i` and `iu` (ES CharacterSetMatcher)**: each class, escape and `.` supplies (S, invert) according to the syntax's compilation rule. `[^…]` is (contents, true); `\W`, `\D`, and `\S` supply their specified complement sets with invert = false. A symbol c matches iff (∃ s ∈ S: Canonicalize(s) = Canonicalize(c)) XOR invert. Do not replace the contents of a negated bracket class with its complement before the existence test: under `i`, `[^k]` must reject `K`, but folding "everything except k" would accept it. Under `iu`, the word set includes the additional characters folding to ASCII word characters, so `\W` rejects ſ and Kelvin sign as well as ASCII letters.
- **Case-insensitive under `v` (`iv`)**: ES2024 v-mode applies MaybeSimpleCaseFolding while compiling sets; complements use the folded universe and set operations act on folded operands. Keep `iu` and `iv` atom tables separate, but do not require all constructs to differ. In both modes, `[^k]` rejects `k`, `K`, and U+212A, and `\W` rejects those characters plus `s` and U+017F. Test these agreements explicitly. Test `[a--A]` under `iv` as empty and `[a&&A]` as matching both `a` and `A`. An actual cross-mode divergence is `\P{Lowercase_Letter}` on `a`: true under `iu`, false under `iv`; this is an engine diagnostic outside the v1 grammar. See [ECMAScript class compilation](https://tc39.es/ecma262/2024/multipage/text-processing.html#sec-runtime-semantics-compiletoclass).
- **`\s`** is the full ECMAScript WhiteSpace ∪ LineTerminator set, not ASCII whitespace.
- **Lone surrogates** in non-unicode mode are ordinary code units. In `u` mode a surrogate pair is one symbol, and a lone surrogate is its own symbol.

**Unicode data provenance.** Vendor a fixed Unicode data release, recording its version and source-file SHA-256 hashes in a checked-in manifest, including case folding and uppercase mappings. Do not use the host OS's changing Unicode tables. Record the manifest in every run and finding. Engine comparisons involving a known Unicode-version difference are classified as compatibility differences, not automatically as V8 bugs. Selecting and checking in this data is part of milestone 1.

### Default alphabet

Each table draws A and R from a small pool chosen to hit the fragile spots: `a b k s A K S 0 _`, space, `\n`, U+017F `ſ`, U+212A (Kelvin sign), U+2028, and one astral char (U+1F600). Enumerated class templates use pool-member bits and an "other" bit that selects a negated spelling over excluded pool members, for example `[^a\n]`. This is a syntax template, not a complete partition of Unicode for case folding. Evaluate membership from the actual class syntax and pinned Unicode rules; never fold or combine sets by treating every out-of-pool character as equivalent. Predefined escapes, ranges, and `v` set expressions retain their own syntax descriptions. A and R are short (default length 1–8, max 15), measured after UTF-16/code-point decoding for the selected flags. Reject a draw exceeding that limit, including astral draws that expand into two non-unicode positions.

The resolved configuration contains a finite, ordered atom inventory and quantifier-parameter inventory. Class nesting, member counts, quantifier bounds, and printed pattern length have explicit limits. `arg` indexes a parameter inventory of at most 65,536 entries per op; reject configurations exceeding that representation rather than truncating IDs. Validate a conservative printed-length bound for every tree through max_size, including groups, capture names, and wrappers, against max_pattern_bytes; do not silently reject oversized samples and thereby change the specified distribution. Store the resolved inventories in the run manifest.

### Syntax rules the printer must follow

The printer emits only syntactically valid regexes, so a `SyntaxError` is always a finding (a printer bug or a V8 bug).

- A quantifier body that is not a single unquantified atom (including assertions, lookarounds, alternations, concatenations, and already quantified expressions) is wrapped in `(?:…)`. This sidesteps Annex B quantified-lookahead rules and prevents invalid stacked quantifiers.
- Alternation inside concatenation is parenthesized by precedence.
- Literal escaping depends on mode. Outside classes, escape `^$\.*+?()[]{}|/`. Inside classes in `u` mode, escape `\ ] - ^`. Inside classes in `v` mode, also escape `( ) [ ] { } / | -` and never emit a doubled class punctuator (`&&`, `!!`, `##`, `$$`, and so on).
- Non-printable or non-ASCII symbols are emitted as `\uXXXX` in non-unicode mode and as `\u{…}` in `u`/`v` mode. Raw non-ASCII characters never appear in the pattern text.
- **Astral and surrogate symbols.** The printer works on decoded symbols, and each literal symbol is printed as one regex atom; non-ASCII symbols use one escape:
  - *Non-unicode mode.* The astral pool char contributes two symbols, its high and low surrogate (U+D83D and U+DE00 for U+1F600). Each is printed on its own as `\uD83D` or `\uDE00`. A literal astral char is therefore a concatenation of two atoms, and a class containing both halves is printed as `[\uD83D\uDE00]`, meaning "either code unit". The printer never emits raw astral characters or `\u{…}` in this mode.
  - *`u`/`v` mode.* The astral char is one symbol and is printed as `\u{1F600}`. If lone surrogates are added to the pool, they are printed as `\u{D83D}` and `\u{DE00}`. Never print adjacent lone-surrogate atoms as `\uD83D\uDE00`: those escapes merge into one astral atom in Unicode modes. The braced escapes preserve the separate atoms; neither should match one half of an astral input symbol.
  - Class ranges are emitted only between symbols of the same kind (both BMP non-surrogate, both surrogate, or both astral in `u`/`v`). In practice the pool is small enough that the printer emits enumerated members and no ranges, except for the `[a-c]`-style atoms the grammar defines explicitly.
  - For every pool symbol and flag set, test the printed literal using the full-match wrapper below against every pool symbol and representative out-of-pool case variants. Without `i`, it matches only the same decoded symbol; with `i`, it matches exactly the Canonicalize equivalence class among the tested subjects. Include empty and multi-symbol subjects, paired and lone surrogates, and multiline subjects to test the wrapper separately.

### Full-match wrapper

Each regex r is tested as a full match with `RegExp.prototype.test`:

- Without `m`: `^(?:r)$`.
- With `m`: `(?<![\s\S])(?:r)(?![\s\S])`, because `^`/`$` would otherwise also match at line breaks and the test would no longer check a full match.

`g` and `y` are never used, so `lastIndex` never matters.

The `m` wrapper contains lookarounds even when the body does not. V1 therefore skips all `m` cases in optional `linear` mode with reason `multiline-wrapper`, and reports this loss of coverage. Do not substitute an unanchored `exec` plus a match-length check: the first successful alternative need not be the one that consumes the entire subject. Unsupported results never count as agreement or a semantic mismatch.

V8 quirk: the ES empty-iteration check ("an iteration of a min-zero quantifier that matches empty fails") does not change full-match booleans, because an empty iteration contributes only (i, i), which `I` already contains. It is ignored in v1.

## Data structures

Relations and productions use flat arrays and integer IDs. Sampling uses bounded arenas and reusable scratch buffers; table construction, publication, and finding persistence have separately budgeted allocations.

| Structure | Representation | Purpose |
| --- | --- | --- |
| `Rel(N)` | `[N]uN` rows, comptime N ∈ {8, 16} (n ≤ N−1) | One span relation; product is N row ops, closure is Warshall on rows |
| `PairId` | `u32` | Interned (rel\_A, rel\_R) pair, the grammar nonterminal |
| `Interner` | Open-addressed hash table keyed by the pair (16 or 64 bytes), Robin Hood probing, arena-backed | Hash-consing; dedups behaviorally equal subregexes |
| `Prod` | `{op: u8, arg: u16, lhs: PairId, a: PairId, b: PairId}` (16 bytes; `b` unused for unary), in a flat `ArrayList` sorted by lhs, with a per-pair `[start, end)` range | Grammar productions, unique by key `(op, arg, a, b)`. `arg` carries op parameters (quantifier bounds, class id, lazy bit) |
| `ProdSet` | Open-addressed hash set over the production key, used only during the build | Ensures each production is recorded exactly once |
| `MinSize` | `u8` per pair; max_size ≤ 255 | Size of the smallest tree in the retained grammar deriving the pair, which is its admission level |
| `Count` | `f32` log-weights, one flat array; pair X owns the slice for k ∈ [MinSize(X), max_size], found through a per-pair `u32` offset | Approximate weighted derivation mass; accumulate log-sum-exp and build probabilities in `f64`, then check the error against a small-grammar reference |
| `SampIdx` | Per-(X, k) alias table over X's productions with a nonzero term at size k. Built lazily and published with a CAS into a `u32` slot array | Lets one production be chosen in O(1). See "Memory budget" |
| `Atoms` | Precomputed relation per literal, class, and assertion, per flag set | Leaves of the grammar |
| `Case` | `{id: u64, flags: u8, A, R, AST, regex text}` plus table identity and seed triple | Owned case data; IDs are unique within a run |
| `Finding` | Owned case, observed results, failure signature, manifest reference and replay-journal reference | Queued triage work contains no borrowed table IDs or pointers |

## Table build

The pair table is built bottom-up by size and semi-naively. In an uncapped build, each production is considered once at the smallest size where its children can derive it. A capped build retains a deterministic subgrammar.

**Levels.** Level k holds the pairs with MinSize = k, meaning pairs first interned at size k. Level 1 holds the atoms. Level k for k ≥ 2 is built from:

- **Unary ops** (quantifiers with each configured `arg`, lookarounds, groups) applied to every Y in level k−1.
- **Binary ops** (concat, alt) applied once to every ordered (Y, Z) with Y in level k₁, Z in level k₂, and k₁ + k₂ + 1 = k. All ordered splits are included; the reversed pair is already another element of that space and is not emitted again. When Y = Z there is only one ordered pair. Alternation retains operand order even when the resulting relation is equal.

Every selected (Y, Z) combination is visited at MinSize(Y) + MinSize(Z) + 1, and every selected unary application at MinSize(Y) + 1. Each resulting production `(op, arg, a, b) → lhs` goes through `ProdSet`. If lhs already exists, a new production is retained subject to the budgets. Otherwise, admission of the pair and its first production is atomic: reserve both, or retain neither. Levels run through max\_size, the largest configured tree size. A newly admitted pair is never used as a child until its level is finalized.

Sizes no longer live in the productions. A production contributes to W(X, k) at *every* size where its children have mass, through the split sum in "Weighted sampling". Productions are not duplicated per size, so W counts each tree exactly once.

**Budget.** Binary ops cost O(|level k₁| × |level k₂|) per split. The following limits select a sound subgrammar:

1. **`max_pairs`** (default 2²⁰). At the start of each level, including level 1, its new-pair quota is floor((max_pairs − pairs so far) / (max_size − k + 1)). Admit new pairs in enumeration order until the quota is exhausted, then discard new-pair results immediately. Continue recording affordable productions for existing pairs. There is no unbounded candidate interner or reservoir. A discarded pair may be admitted at a later level; MinSize is then its smallest derivation size in the retained grammar. This admission policy is deliberately order-biased, not uniform over candidate pairs.
2. **`max_combos`** (default 2²⁶ per level). If the ordered (split, Y, Z) space exceeds this limit, select a seeded uniform subset without replacement. Stream selected ranks in ascending order using a bounded-memory algorithm; do not materialize the Cartesian product. Enumerate unary ops first by child ID and parameter ID, then binary ranks by split, Y ID, Z ID, and op. Unary enumeration is also subject to the production, work, and byte limits below.
3. **`max_prods`** (default 2²²). Before committing a new production, check this cap. If it would be exceeded, finalize the level and stop enumeration. `ProdSet` compares full keys through production IDs, not fingerprints alone.
4. **`max_count_terms`** (default 2²⁸). At production admission, charge the number of unary terms or binary size-split terms that the counting loops will visit through max_size, based on child MinSize values. This is a conservative bound before zero-weight pruning. If the next production would exceed the limit, finalize the level and stop enumeration. Counting must finish for the retained grammar; never publish partially computed counts.
5. **Byte limits.** Every allocation and capacity increase must satisfy the hard limits below. Required final arrays and scratch capacity are reserved in the admission accounting. If a production cannot be admitted within the table reservation, finalize the level and stop enumeration. Failure to reserve the minimum viable table rejects that build with a resource reason.

Stats report the truncation level and specific cap. Enumeration and budget decisions depend only on the table seed, resolved inventories, effective limits, and generator version, not timing or current free memory. Record these inputs. A background build waits for its global reservation; it does not silently change the effective limits due to lane scheduling.

Further rules:

- By default, skip lookaround application when **both relations are diagonal**, including empty relations. This is a semantic coverage heuristic, not a claim about the body's syntax: one pair can represent assertions, empty groups, and consuming expressions that happen not to consume on these strings. A recorded `allow_diagonal_lookarounds` option disables this heuristic for dedicated campaigns.
- Stats on pairs, prods, combos visited and pairs dropped per level are printed after each build, so blowups are visible.

**After enumeration:**

1. **Usefulness pass.** Optionally walk from start pairs with a bounded (pair, remaining size) frontier, following only productions whose child minimum sizes fit. This is conservative pruning; it need not identify every useless pair. If its workspace limit is reached, abandon pruning and retain the original grammar. Budget both the original and any compacted arrays during this operation.
2. **Renumber** surviving pairs deterministically in original ID order, sort `Prod` by `(lhs, op, arg, a, b)`, and free `ProdSet` and build-only storage.
3. **Count.** Compute W(X, k) bottom-up for k = 1 … max\_size into `Count` (see "Weighted sampling").

### Memory budget

Illustrative component capacities at the default pair/production caps, max_size = 24, and N = 16 (64-byte pair keys), in MiB. These are not a peak-memory guarantee:

| Structure | Size | At caps |
| --- | --- | --- |
| Interner | 64 B key per pair, plus an 8 B slot at load ≤ 0.5 | ~80 MiB |
| `Prod` | 16 B × prods; assert layout size | 64 MiB |
| `ProdSet` (build only) | 4 B production ID × 2 × prods | 32 MiB |
| `Count` | 4 B × Σ_X (max_size − MinSize(X) + 1) | ≤ 96 MiB |
| `SampIdx` slots | 4 B per `Count` entry | ≤ 96 MiB |
| `SampIdx` arena | 12 B per entry, plus headers and alignment | default cap 256 MiB |

**Hard accounting.** `max_table_bytes` (default 1 GiB) covers a table's entire lifecycle, including build arrays, hash capacity, allocator alignment, growth copies, pruning and sorting workspace, counts, start/size indexes, and alias storage. Reserve the worst simultaneously live phase before admitting data, and check every allocation through a budgeted allocator. Estimates may reject a configuration early but never replace allocation checks. Checked arithmetic rejects sizes or offsets that overflow their representations.

`max_host_bytes` (default 4 GiB) bounds all fuzzer-owned dynamic arenas and buffers together, including active, retired, building, and triage-rebuilt tables, per-lane scratch, protocol buffers, and the finding queue. It does not bound d8 child heaps or OS/runtime overhead; report host and child RSS separately. Fixed runtime overhead is measured in the performance gate. At most one replacement table is built at a time; further replacement waits until older batch-held tables are released. Reserve triage capacity before allowing background builds to consume remaining capacity. Configurations must fit the configured lanes and scratch, one active table, one replacement table, and one triage workspace simultaneously; reject configurations that cannot fit instead of waiting forever for an impossible reservation. The per-table admission accounting includes its contribution to required lane scratch so these reservations depend only on the recorded configuration. A table reservation is released only after its last owner is gone.

**Lazy `SampIdx`.** A fully precomputed alias index could reach prods × max\_size entries (gigabytes), so alias tables are built on demand:

- A slot value of 0 means not built; published values encode arena offset + 1. A lane constructs a deterministic alias table in reserved scratch, then reserves arena space with a checked CAS loop that fails without advancing the bump pointer when full. Write the complete table before release-publishing its slot; readers acquire-load the slot. Losing slot publishers waste only their already-budgeted arena reservation. This avoids bump-pointer overflow after repeated full-arena attempts.
- Per-lane scratch is reserved for the largest production list in the admitted table before publication. If caching is disabled or the arena is full, draw from the same scratch-built alias table without caching. Both paths use identical production ordering, arithmetic, and RNG draws. Track cache hits, uncached draws, and wasted reservations. Shared lazy caching is an optional optimization gated by the measurements below; the initial implementation uses scratch-built tables.

## Weighted sampling

Each construct gets a user weight w\_c. The mathematical target is a tree probability proportional to the product of its constructs' weights, conditioned on a chosen size in the materialized grammar. The recurrence is exact; floating-point counts and random draws approximate that distribution:

```latex
W(X, 1) = \sum_{\text{atom } a:\, \mathrm{pair}(a) = X} w_a \qquad
W(X, k) = \sum_{p:\, X \to op(Y)} w_{op}\, W(Y, k-1) + \sum_{p:\, X \to op(Y, Z)} w_{op} \sum_{\substack{k_1 + k_2 = k-1 \\ k_1 \ge \mathrm{MinSize}(Y),\ k_2 \ge \mathrm{MinSize}(Z)}} W(Y, k_1)\, W(Z, k_2)
```

Each production occurs once in the sums (it is unique by key), so W(X, k) is exactly the total weight of the distinct trees of size k deriving X in the materialized grammar.

Sampling a tree of size k from X happens in two steps, then recurses:

1. **Production:** one draw from the `SampIdx` alias table for (X, k).
2. **Split (binary productions only):** pick k₁ by inversion over the at most max\_size − 2 split terms W(Y, k₁)·W(Z, k − 1 − k₁), computed in log space on the fly. These are not cached, since the scan is short and cache-resident.

For each size k, let Z_k = Σ over start pairs X of W(X, k). Build a start-pair alias table only when Z_k > 0. If D(k) is the configured size weight, draw sizes from D'(k) = D(k)·1[Z_k > 0] / Σ_j D(j)·1[Z_j > 0]. Start pairs are then drawn in proportion to W(X, k). This conditions the requested size distribution on feasible sizes; it does not weight sizes by Z_k. Report excluded sizes and the resulting distribution.

Reject a table if that denominator is zero. Reject A = R before building; other inseparable pairs, such as `a` and `A` under `i`, may be detected early or through zero start mass. Derive each retry seed from (global seed, table sequence, attempt number). After `max_table_attempts` (default 64) consecutive failed attempts, stop the campaign with a diagnostic listing zero-mass and resource rejection counts. Never spin forever or construct an empty alias table. The old active table may serve its remaining configured samples while replacement attempts run, but cannot hide retry exhaustion.

1. Weights come from a TOML config, for example `star = 3.0`, `lookbehind = 5.0`, `backslash_b = 2.0`, `alt = 1.0`. Accept finite nonnegative weights; zero disables a construct. Reject NaN, infinity, negative values, and a size distribution with no positive weight.
2. Size is drawn from a configurable distribution (default uniform 4–24 nodes) so both tiny and deep regexes appear.
3. Weights are applied at table-build time, so changing them means recomputing counts and sampling indexes; rebuild timings are measured rather than assumed.
4. Optional adaptive mode: constructs present in confirmed bug-finding cases get their weight bumped by a multiplicative factor, capped at 10× the base. Apply updates only at table boundaries and persist the exact effective weights and update sequence.

Counts use log-space f32 storage, with −∞ representing zero mass and f64 log-sum-exp accumulation. Reject unexpected NaN or +∞ as model failures. Tiny positive probabilities can round to zero; this affects sampling coverage, not the oracle's validity. Measure error against an exhaustive f64 reference on small grammars, including extreme permitted weight ratios, before making an accuracy claim. Do not promise a universal 1e−5 relative error.

Initialize a fresh xoshiro256** stream per case from (global seed, lane id, case index), using a versioned seed-expansion algorithm. Reproduction also requires the table seed, actual A/R/flags, resolved inventories and effective limits, effective weights, Unicode manifest, generator source/build identity, driver hash, and numerical implementation version. Save a digest of the finalized grammar and counts; verify it on reconstruction. Asynchronous table swaps and adaptive updates need not reproduce an entire run's scheduling from one seed, so record each case's actual table identity. Printed pattern and AST are authoritative saved artifacts even if later software cannot regenerate identical sampling decisions.

## Parallel pipeline

The working hypothesis is that d8 dominates steady-state execution cost. Measure generation, counting, transport, and engine time separately before choosing concurrency. The initial implementation is single-lane; the following pool is the intended measured extension.

```
            ┌────────────── shared PairTable (immutable grammar, owned batch references) ───────┐
            │                                                                                      │
   lane 0 thread: sample batch ──► d8[interp]  d8[native]  d8[tierup]  (d8[linear]) ──► compare ──┐
   lane 1 thread: sample batch ──► d8[interp]  d8[native]  d8[tierup]  (d8[linear]) ──► compare ──┤
   …                                                                                              ▼
                                                                         findings queue (mutex) ─► triage thread
                                                                                                   (shrink, dedup, repro)
```

- A **lane** is one thread plus one d8 process per active mode. It samples a batch, sends identical cases to participating modes through the nonblocking event loop, compares results, and persists findings. Start with one batch in flight; allow two only after the transport tests and throughput gate pass. Both partially sent and fully sent batches count toward this limit.
- **Process budget:** `--jobs 0` sets the maximum sampling d8 processes to `sysctl hw.physicalcpu`. With M active modes, lanes = floor(jobs / M); validate jobs ≥ M rather than silently exceeding the limit. Report unused remainder slots. Reserve at most one additional triage/verification child, explicitly reported outside the sampling budget; it runs modes sequentially. An ASan pool consumes an explicitly configured additional process budget.
- **Scheduling on macOS:** there is no CPU pinning. Request `QOS_CLASS_USER_INITIATED` for lane threads and spawned d8 processes where the APIs are available. Check return codes and report fallback behavior. QoS is a scheduling hint, not a guarantee of P-core placement or full-core utilization.
- **Table ownership:** publication uses a short mutex-protected exchange of a strong reference. Each batch acquires its own reference under that mutex before sampling and releases it only after all its mode results are resolved and any finding data has been copied. A retired table is freed when its last reference is released, including references from either outstanding batch. An unprotected atomic load followed by a reference increment is not safe. More elaborate reclamation is deferred until measurements justify it.
- **Finding ownership and backpressure:** before enqueueing, persist an owned AST, pattern, subjects, results, manifest, and replay-journal reference. Queued findings never borrow PairIds or table memory. The queue is bounded by both `max_pending_findings` (default 256) and `max_pending_finding_bytes` (default 64 MiB). Reserve additional persistence buffers for all admitted in-flight batches. When full, stop generating new work, drain in-flight I/O, and persist any additional findings to disk before waiting for queue space; load them into triage in bounded groups. Disk exhaustion or failure to persist stops new work with an explicit error; findings are never silently dropped. Triage can reconstruct one table at a time in its reserved workspace, verify its digest, and release it after processing.

## d8 harness and oracle

Sampling d8 processes are long-lived and run `driver.js`. Measure startup cost on the target build. Spawn on startup, after failure, and on bounded recycling; dedicated fresh-process verification is also permitted and measured separately.

### Wire protocol (text, line-based)

The driver uses d8's `readline()` for stdin, so the protocol is newline-delimited and all string content is JSON-escaped (A and R may contain `\n`, U+2028 or lone surrogates).

1. **Request:** one line per batch, a JSON array `[batch_seq, [[flags, A, R, regex], …]]`, normally with 256–1024 cases. `regex` is the unwrapped printed body; the driver applies the specified wrapper exactly once. Batch size is additionally limited by `max_request_bytes` (default 1 MiB). The generator's `max_pattern_bytes` (default 16 KiB) and subject limits must allow every individual case to fit. Split batches by encoded byte length; do not assume a 100 KB upper bound.
2. **Response:** one line per batch, `batch_seq` + space + two hex digits per case, giving 8 result bits:
   - bit 0: `test(A)`
   - bit 1: `test(R)`
   - bit 2: `SyntaxError` at construction
   - bit 3: any other exception (for example stack overflow on deep nesting)
   - bit 4: `test(A)` on the second run (`tierup` mode only; always 0 in other modes)
   - bit 5: `test(R)` on the second run (`tierup` mode only; always 0 in other modes)
   - bit 6: unsupported or deliberately skipped (`linear` mode only); all other bits zero for this case
   - bit 7: reserved, must be zero
3. **Startup:** the driver prints one line `ready <version()>`. Enforce a configurable startup deadline (default 10 s), record the version and process flags, and reject malformed or missing handshakes. Probe supported modes in short-lived children before starting the campaign.
4. **Transport:** set the parent's stdin write-end and stdout/stderr read-ends nonblocking. Use one `poll` loop per lane to multiplex writable input and readable output/error for all its children, with bounded per-fd work for fairness. Handle short reads/writes, EINTR, EAGAIN, EOF, EPIPE, and child exit; suppress SIGPIPE for these writes. Drain stdout and stderr while requests are still being written. Partial lines live in bounded buffers; enforce response sequence, hex length, and allowed-bit validation. Malformed protocol data is a harness/protocol finding, not a match result. Keep blocking disk persistence and triage off the poll loop through bounded worker queues so they cannot prevent deadline checks for already admitted work.
5. **Deadlines:** use a monotonic absolute deadline starting when a batch is admitted to a child's send queue, including time blocked behind the preceding batch. The same deadline governs partial writes, execution, and response reads; every poll uses the earliest pending deadline. A hung first batch therefore cannot trap the lane while writing the second. Expiry kills and reaps the child, closes its descriptors, and marks every unanswered batch for replay. Queued batches are unresolved, not automatically blamed for the hang.
6. **Output bounds and flushing:** retain a bounded stderr tail (default 1 MiB per child) while continuously draining excess and counting truncated bytes; retain full diagnostics for isolated replays subject to the output budget. Verify that `print` flushes by keeping a child alive after a request and requiring its response before sending the next. The supported driver requires a verified flushing output primitive; absence is a startup incompatibility, not an assumed `write`/flush fallback.

### Modes

Flags are process-wide, so each mode is its own d8 process:

| Mode | d8 flags | Expected per case |
| --- | --- | --- |
| `interp` | `--regexp-interpret-all` | A=1, R=0, no exception |
| `native` | `--no-regexp-tier-up` (compile to native code immediately) | A=1, R=0, no exception |
| `tierup` | `--regexp-tier-up --regexp-tier-up-ticks=1`, if successfully probed | Run `test(A)`, `test(R)`, `test(A)`, `test(R)` on the same object; expect 1, 0, 1, 0. This tests repeated execution under tier-up settings, but is not itself proof of a transition |
| `linear` (optional) | `--enable-experimental-regexp-engine`, driver adds `l` | Skip `m` with reason `multiline-wrapper`. Otherwise, if ordinary construction succeeds but construction with `l` throws SyntaxError, mark `engine-unsupported`. Other exceptions remain findings. Supported cases expect A=1, R=0 |

Findings: any participating mode's deviation from its expected bits, including a single-mode oracle mismatch. Compare modes only after excluding unsupported/skipped entries and decoding their different result layouts. Report execution, skip, and unsupported counts per mode; skipped cases contribute neither agreement nor mismatch. The host knows `multiline-wrapper` from flags; the other bit-6 reason is `engine-unsupported`.

**Tier coverage.** V8 can reuse regexp data through a cache keyed by source and flags; constructing a new object does not guarantee uncompiled data. Short subjects avoid a known eager-compilation trigger but do not establish the actual tier. Track source/flag novelty within each process using a bounded set; recycle when that set reaches its configured cap. Report first-seen and repeated-pattern executions separately, without calling first-seen executions verified transitions. See [V8's regexp compilation cache](https://raw.githubusercontent.com/v8/v8/main/src/regexp/regexp.cc).

A separate verification campaign uses fresh processes and, where supported, regexp tier tracing or an instrumented d8 build to observe interpreter execution followed by native execution for the same pattern. Probe trace flags by actually launching them: appearing in `--help` does not prove a flag is writable or that diagnostics were compiled in. Tracing uses a separate diagnostic channel/parser and cannot contaminate the batch protocol. If reliable observation is unavailable, report transition coverage as **unverified** while retaining the semantic repeated-execution tests. Save actual call order, subjects, diagnostics, and process flags for verified transitions and findings.

Optional flags worth rotating as extra modes: `--no-regexp-optimization`, `--regexp-backtracks-before-fallback=0` (with `--enable-experimental-regexp-engine-on-excessive-backtracks`), `--no-regexp-peephole-optimization`. Discover candidates through `d8 --help`, then probe each full flag combination with the driver and a known-answer case. Disable unavailable optional modes with a recorded reason; fail startup if an explicitly required mode is unavailable. Record the resolved mode set.

### Timeouts, crashes, recycling

1. The batch deadline is max(2 s, 2 s × case_count / 512) by default, configurable and recorded. On timeout, kill and reap that child, preserve its journal, and replay unanswered work in a dedicated child. Bisect only after confirming reproduction; a batch can exceed its deadline through aggregate cost without one independently slow case. Keep unresolved and sequence-dependent timeouts as such. Slow cases go in `slow/`, separate from semantic findings.
2. For crashes, preserve exit status, stderr tail, outstanding batches, and process journal. Attempt isolated reproduction first; if that fails, replay the ordered prefix and minimize the sequence instead of declaring the case non-reproducible or blaming the last input. The dedicated triage child is subject to the same I/O limits and deadlines.
3. Recycle after a configured case count, novelty-set entry/byte cap, or replay-journal byte cap, whichever comes first. Defaults are 1 million cases, 100,000 distinct patterns or 16 MiB of novelty-set storage, and 256 MiB of journal data per process. The novelty set uses collision-checked source/flag equality and counts toward max_host_bytes. Journals persist exact requests and call-order policy from process startup before requests are sent. Reserve their storage before admission; split a batch when needed to fit remaining capacity, or recycle after draining admitted work. Validate that each cap can accommodate at least one maximum-size case. Do not truncate a live process's history. Unreferenced journals may be deleted only after their process has retired and all its cases are resolved; journals referenced by findings remain available. These limits bound retained process history, not child heap size.

### d8 build

Build d8 from V8 source for arm64 macOS. The recommended args are `is_debug=false dcheck_always_on=true v8_enable_slow_dchecks=false`, so internal invariant violations surface as crashes at near-release speed. An optional second build with `is_asan=true` can run as a separate lane pool for memory-safety crashes.

Crash reporting can add substantial overhead on macOS. Where supported, request null crash exception ports with `posix_spawnattr_setexceptionports_np(attr, EXC_MASK_CRASH | EXC_MASK_CORPSE_NOTIFY, MACH_PORT_NULL, EXCEPTION_DEFAULT, 0)`. Check API availability and return codes, and verify the behavior with a controlled crashing helper on each supported OS release. Treat suppression as best-effort; the harness must still reap signal exits and capture stderr when suppression is unavailable. No system-wide crash-reporting changes are required. Isolated reproduction runs in the dedicated triage child.

## Triage, shrinking and dedup

Every shrink candidate is evaluated by the relation model and must retain A=1, R=0 before engine testing. Acceptance also preserves the recorded failure predicate (wrong result and affected subject, exception kind, or crash signature), not merely any failure. Keep the original finding even when minimization fails or exhausts its work budget.

1. **Tree shrink:** optionally reconstruct the original retained grammar from its manifest and verify its digest in triage's reserved workspace. Try a smaller witness for the same pair, then smaller trees whose recomputed root pair is a start pair. The table stores productions, not an enumeration of every smallest witness; derive witnesses by bounded dynamic programming. If reconstruction is unavailable, use structural AST reductions and direct relation evaluation, recording that limitation. No original table reference is needed.
2. **String shrink:** drop or replace decoded symbols in A and R, re-decode under the current flags, and evaluate the current AST directly on the new strings. Building an entire generation grammar is unnecessary. Reject changes that lose the accept/reject separation.
3. **Flag shrink:** remove flags one at a time, or swap `v` for `u` only when the syntax is valid there. Recompute atom semantics, positions, wrappers, and oracle bits for every attempt; syntactic compatibility alone does not imply semantic equivalence.
4. **Mode and history shrink:** minimize the modes required to demonstrate the failure; one mode suffices for an oracle disagreement. Preserve the exact execution sequence for process-state-dependent findings, then minimize the prefix and call sequence under the same failure predicate. Report an irreducible sequence rather than forcing a single-case reproducer.
5. **Grouping and dedup:** group by failure kind, affected modes, and construct multiset for navigation only. Assign each distinct reproducer its own content hash over exact UTF-16 subjects, pattern, flags, mode/build identity, failure predicate, and required execution history. Automatically coalesce only byte-identical canonical artifacts with collision-checked equality. Different literals, bounds, structure, and histories remain separate. Crash stacks or matching construct multisets may suggest a common root cause but do not authorize deleting a reproducer. Each group may link to a preferred small example while retaining all members.
6. **Output:** persist one directory per finding ID, plus group indexes, containing:
   - original and minimized ASTs, patterns, subjects, and observed/expected results;
   - `repro.js`, using JSON-escaped `new RegExp` construction and the actual wrapper and call order; for sequence-dependent failures include the minimized prefix and original journal reference;
   - `manifest.json`: seed triple, table seed and identity, resolved config/inventories, effective limits and weights, Unicode version/hashes, grammar/count digest, generator source/build identity, driver hash, and numerical implementation version;
   - exact flags per mode, d8 version and binary hash, V8 revision/build args when available, OS/architecture, deadlines, exit status, diagnostics, and tier-verification status;
   - replay instructions and confirmation status under the recorded build. A saved case is not called a confirmed V8 bug merely because the model and engine disagree.

**Sanity mode** cross-checks a sample of cases against independent engines, to catch bugs in the fuzzer's own relation semantics before blaming V8:

- JavaScriptCore's `jsc`, when available, through an explicit configurable path; do not assume every macOS installation supplies a usable shell.
- SpiderMonkey's `js` shell through an explicit configurable path, optionally.
- Node is not independent, since it uses V8.

If V8 and JSC agree with each other but disagree with the oracle, suspect the model first.

**Atom self-check** at startup: for every configured consuming atom, flag set, and alphabet symbol, compare model membership against d8 in `interp` mode and available independent engines. Test assertions in whole-string contexts at each position, including beginning/end, line breaks, word boundaries, and empty input; they are not single-character membership predicates. Probe each shell's features and provide adapters for stdin, version, and flushing APIs. Unsupported features are skips. Discrepancies are reported, never silently adopted; adopting V8's answer would hide the bugs being sought.

## Performance budget and tricks

The throughput goal is to minimize avoidable engine idle time within the resource limits. The figures below are hypotheses to measure on the target machine, not established timings or acceptance guarantees. Correctness, bounded memory, and replayability take precedence over utilization.

| Stage | Initial hypothesis / complexity | Measurement |
| --- | --- | --- |
| Relation product | ~20 ns aspirational; scalar work depends on row density | Benchmark scalar and vectorized implementations for N = 8 and 16, verify generated code |
| Interner lookup | ~30 ns aspirational | Measure load factor, key size, collisions, and cache effects |
| Table enumeration | 1–50 ms hypothesis for small builds | Report atoms, pairs/prods by level, visits, rejections, truncation, peak bytes, and elapsed time |
| Weighted counting | O(P_unary × K + P_binary × K²), K = max_size | Report visited terms, count/index time, and memory separately; enforce max_count_terms |
| Sample and print | 0.2–1 µs hypothesis with caching | Measure cached/uncached paths, split scans, and printing separately |
| d8 execution and transport | 5–50 µs per case hypothesis | Separate startup, encoding, I/O, fresh patterns, repeated patterns, and engine time |

At P_binary = 2²² and K = 24 with both child minimum sizes equal to 1, the unpruned recurrence visits 253 splits per production, over 10⁹ terms. Pair and production caps alone therefore do not establish a millisecond build budget. The independent counting-work cap can truncate enumeration before the production cap.

**Performance gate.** Before enabling shared lazy indexes, parallel table construction, or the multi-lane pool, run the single-lane prototype on a fixed, checked-in corpus of seeds covering length extremes, flag sets, repeated subjects, and deliberately tiny budgets. Verify oracle agreement on the supported corpus, finite retries, correct replay, and allocation-cap compliance. Publish timings by stage, peak managed bytes and RSS, zero-mass rates, sampling-error checks, and engine idle time. Use these measurements to select defaults. Parallel enumeration, if later justified, must merge results in the same deterministic admission order and account for worker scratch memory.

Tricks:

- **Amortize tables:** initially try 10⁵–10⁶ samples per table, then tune using measured duplicate-pattern rates and coverage across subjects and flags.
- **Alias method:** Walker alias tables per (pair, size), built lazily and shared across lanes (see "Memory budget"), so each production choice is two random numbers and one lookup.
- **Comptime N:** instantiate `Rel` for N = 8 and 16 so short strings (n ≤ 7) use `u8` rows and fit more pairs per cache line.
- **Batch in flight:** benchmark one versus two outstanding batches only with the deadline-aware nonblocking transport.
- **Cheap compare:** decode and validate result bits before comparing supported modes against the oracle; add a bytewise fast path only if it preserves exception, skip, and tier-result handling.

## Build layout, CLI and milestones

One Zig package with an exact compiler version pinned in a toolchain file and CI; `build.zig.zon` also declares the supported minimum version. Target `aarch64-macos`. Validate with safety checks enabled before benchmarking `-OReleaseFast`. Use POSIX and Darwin APIs (`posix_spawn`, exception-port spawn attributes where available, nonblocking fds, `poll`, `sysctlbyname`, pthread QoS).

| File | Role |
| --- | --- |
| `src/rel.zig` | Comptime-generic span relation and its ops |
| `src/alphabet.zig` | Symbol model (code unit vs code point), line terminators, word chars, Canonicalize for `i` / `iu` |
| `src/atoms.zig` | Literal, class, and assertion relations per flag set |
| `src/table.zig` | Interner, budgeted bottom-up pair table, usefulness pruning, weighted counts |
| `src/sample.zig` | Alias tables, sampler, mode-aware regex printer and escaping |
| `src/harness.zig` | d8 spawn (`posix_spawn` + QoS + null crash exception ports), line protocol, `poll` timeouts, bisection, recycling |
| `src/lane.zig` | Per-lane loop: sample, fan out to modes, compare |
| `src/shrink.zig` | Tree, string, flag and mode shrinking plus dedup buckets |
| `src/main.zig` | CLI, config loading, lane spawn, stats line |
| `driver.js` | Batch execution and wrapper/call-order policy, with shell adapters for optional independent-engine checks |

CLI: `irx --d8 ./d8 --config weights.toml --jobs 0 --seed 42 --out findings/ [--modes interp,native,tierup] [--jsc PATH]`. Here `--jobs 0` sets the sampling-process ceiling to physical-core count; print the actual lane/process allocation and separate triage allowance. A once-per-second stats line shows cases/s, stage times, pairs/prods, managed bytes and RSS, pending findings, zero-mass retries, per-mode executed/skipped counts, verified/unverified tier coverage, slow cases, and restarts. Save the resolved configuration before executing cases.

1. `Rel` ops, pinned Unicode data, and the alphabet/flag model. Cross-check against a naive backtracking matcher in Zig and curated ECMAScript examples, including backward matching, empty repetitions, and surrogate boundaries.
2. Deterministic, budgeted table build and weighted counts for literals, concat, alt, star and empty. Use all-one weights initially. Exhaustively enumerate small grammars to validate counts, production uniqueness, feasible-size conditioning, and numerical sampling error. Exercise zero-mass and resource rejection.
3. Single-lane d8 harness (`interp` only), persistent findings and replay metadata, nonblocking transport, deadlines, and bounded journals. Test partial reads/writes, a child that stops reading during batch 1 while batch 2 is sent, stderr flooding, malformed responses, EOF, and child death. Recovery must meet the deadline without a watchdog thread.
4. Full v1 constructs and flag semantics, consuming-atom and assertion self-checks, optional independent-engine adapters, and the measured single-lane performance gate. Resolve model discrepancies and publish benchmark results before advancing.
5. Shrinker and lossless grouping/dedup, including flag/string revalidation and sequence-dependent reproduction. Verify queued findings survive table retirement, queue saturation applies backpressure, and distinct reproducers sharing a construct multiset are retained.
6. All execution modes, explicit linear skips, fresh-process tier verification where available, and resource-bounded multi-lane publication/reclamation. Stress swaps with two outstanding batches, full alias arenas, and simultaneous triage. Enable shared alias caching or parallel construction only when measurements justify them and deterministic replay tests pass.
7. User-configurable weights and optional adaptive updates with recorded effective configuration. Repeat numerical and replay checks for nonuniform weights and changing tables.
