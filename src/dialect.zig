//! Regex dialect component. A Dialect describes *what a regex means* in one
//! regex family: character predicates, case-insensitive matching, anchor rules,
//! pattern syntax, and constraints on strings, flags and grammar. It says nothing
//! about the oracle's question: today irx asks "does r fully match w?", which the
//! relation model answers from the span relation; a future match-range oracle
//! (leftmost/longest spans, captures) can reuse the same Dialect unchanged and add
//! its own engine-priority semantics alongside.
//!
//! Adding a dialect = one file in src/dialects/ registered in `all`, plus a
//! self-check that reaches zero mismatches against a reference engine.
const std = @import("std");
const alpha = @import("alphabet.zig");
const atoms = @import("atoms.zig");

pub const Flags = alpha.Flags;

/// How code points that need escaping are spelled in patterns.
pub const Escape = enum {
    /// ECMAScript: \uXXXX without u/v, \u{H} with u/v.
    es,
    /// Perl/PCRE family: \x{H}.
    x_brace,
};

/// How subjects are decoded into symbols.
pub const Strings = enum {
    /// ECMAScript: code units without u/v, code points with u/v (both allowed).
    es,
    /// Code points only: every flag set gets `u`, no lone surrogates, no `v`.
    code_points,
    /// UTF-16 code units only (.NET): no `u`/`v`; astral characters are two symbols.
    utf16_units,
};

/// Named-group spelling.
pub const NamedGroup = enum { angle, p_angle, plain_capture };

/// How the self-check spells "any single character".
pub const AnyChar = enum { empty_negated_class, space_or_nonspace };

/// combining: a character and the marks after it (Boost; CR LF stays two clusters).
pub const Grapheme = enum { none, extended, extended_gb9c, combining };
pub const FullFold = enum { none, literals, classes };

pub const Dialect = struct {
    name: []const u8,
    /// Character predicates over code points. `isWord` gets flags because some
    /// dialects (ES with iu/iv) widen \w under case-insensitivity.
    isLineTerminator: *const fn (u21) bool,
    isSpace: *const fn (u21) bool,
    isWord: *const fn (u21, Flags) bool,
    isDigit: *const fn (u21) bool,
    /// Optional replacement for the generic CharacterSetMatcher on consuming
    /// atoms (dialects whose case-insensitive class rules differ, e.g. Swift).
    matchAtom: ?*const fn (*const atoms.AtomSpec, Flags, u21) bool = null,
    /// `^` under multiline also matches after a newline that ends the string.
    caret_after_trailing_newline: bool = true,
    /// `^`/`$` are always line anchors, regardless of the m flag (Ruby).
    anchors_always_multiline: bool = false,
    /// Word set used by \\b/\\B when it differs from \\w (null = isWord).
    isBoundaryWord: ?*const fn (u21, Flags) bool = null,
    /// Full override for \\b at position i of w (Emacs: buffer edges, script changes).
    boundaryAt: ?*const fn ([]const u21, usize, Flags) bool = null,
    /// `^` under multiline never matches at the end of input (Java: not even in "").
    caret_m_never_at_end: bool = false,
    /// `$` without multiline also matches before a final line terminator (Perl, Java).
    dollar_before_final_terminator: bool = false,
    /// "\\r\\n" is one line terminator: no ^/$ between \\r and \\n (Java, ICU).
    crlf_atomic: bool = false,
    /// With crlf_atomic, `^` may still match between \\r and \\n (ICU); only `$` treats CRLF as one.
    caret_splits_crlf: bool = false,
    escape: Escape = .es,
    any_char: AnyChar = .empty_negated_class,
    strings: Strings = .es,
    /// Case-insensitive key: c matches s iff fold(c) == fold(s) (set members
    /// included). null = ECMAScript Canonicalize.
    fold: ?*const fn (u21) u21 = null,
    named_group: NamedGroup = .angle,
    word_boundary: []const u8 = "\\b",
    nonword_boundary: []const u8 = "\\B",
    /// The empty atom may also print as nothing: `(?:|a)`, `a|`, `(?=)` (fuzz cases only;
    /// self-check keeps `(?:)`). POSIX ERE rejects empty branches.
    bare_empty: bool = true,
    /// Inline flag groups (?i:…) / (?-i:…) are supported, for the flags in scoped_mods
    /// (ast.fmod_*); dotall_letter spells s (Ruby: m).
    scoped_flags: bool = false,
    /// Mutation mode (atomic groups, possessive quantifiers, backreferences): which the engine has.
    atomic_groups: bool = false,
    possessive: bool = false,
    backrefs: bool = false,
    /// A backreference to a group that has not participated matches empty (ECMAScript) rather
    /// than failing (Perl, PCRE and most others).
    backref_unset_matches_empty: bool = false,
    /// Possessive spellings exist for counted loops too (x{2,3}+); Ruby reads that as {2,3} then +.
    possessive_counted: bool = true,
    /// Backreferences to named groups are spelled \k<name>, and with any named group present a
    /// numbered reference is an error (Onigmo, Oniguruma).
    backref_by_name: bool = false,
    /// Loop bodies' captures are cleared per iteration (capture model hint for the oracle).
    reset_loop_captures_hint: bool = false,
    /// \h \H \v \V (horizontal / vertical whitespace) are generated, with these sets.
    hv_escapes: bool = false,
    /// v-mode class strings (\q{…}) are compared case-insensitively under i. Irregexp compares
    /// the folded string against the raw subject (IRX-V8-5), so its targets keep \q out of i.
    qstr_ignore_case: bool = true,
    /// \X: one extended grapheme cluster (UAX #29) from the current position, atomically;
    /// `extended_gb9c` adds rule GB9c (Indic conjuncts, Unicode 15.1).
    grapheme_escape: Grapheme = .none,
    /// Follow UAX #29 for Prepend + emoji and regional indicator + Extend (PCRE2 does not:
    /// IRX-PCRE2-6).
    grapheme_prepend_pict: bool = true,
    /// Full case folding under i: a pattern character with a multi-character fold (ß → ss)
    /// matches subject strings with that fold. `literals`: literal characters; `classes`: also
    /// members listed in a non-negated class (not ranges).
    full_fold: FullFold = .none,
    /// Characters that may appear in patterns but not in subjects: with full folding, a subject
    /// ß would also be matched by pattern sequences like `ss`, which the atom model cannot see.
    pattern_only: []const u21 = &.{},
    /// Scoped extended mode (?x:…) is supported: whitespace and # comments are ignored.
    extended_mode: bool = false,
    isHSpace: *const fn (u21) bool = defaultHSpace,
    isVSpace: *const fn (u21) bool = defaultVSpace,
    /// Named groups in different alternatives may share a name (ES2025 duplicate named groups).
    duplicate_names: bool = false,
    /// Under i, \p{…} also matches the multi-character case folds of its members (Onigmo:
    /// \p{L} matches "ss" via ß, "ff" via ﬀ): not modelled, so no \p under i.
    props_multi_fold: bool = false,
    scoped_mods: u8 = 1 | 2 | 4,
    dotall_letter: u8 = 's',
    /// `\p{…}` / `\P{…}` general categories are supported (props_need_u: only with u/v, ES).
    unicode_props: bool = false,
    props_need_u: bool = false,
    /// How case-insensitive matching treats a property (PropCase).
    prop_case: PropCase = .equivalence,
    /// A bare empty is also accepted inside lookarounds (nim-regex rejects `(?<=)`, `(?=)` and
    /// `(?<=|b)`, but accepts `(?=(?:))` and `(?=a|)`).
    bare_empty_in_lookaround: bool = true,
    /// A counted repeat {m,n} (any form but * + ?) may contain a lookaround (nim-regex aborts
    /// the compiler: NIM-1).
    counted_lookaround: bool = true,
    /// The empty atom may also print as an empty capture `()`.
    empty_capture: bool = true,
    /// \W \D \S negate after case folding (no case variant is in the positive
    /// set) instead of complementing before folding as ECMAScript does.
    negated_escapes_invert: bool = false,
    /// \\w \\d \\s and their negations are plain property tests, unaffected by i.
    escapes_ignore_case: bool = false,
    /// `.` matches everything unless m, and excludes \\n under m (Racket multi mode).
    dot_all_unless_m: bool = false,
    /// Grammar restrictions for constructs the engine does not support.
    allow_lookahead: bool = true,
    allow_lookbehind: bool = true,
    /// Assertions the engine accepts anywhere in a pattern (resharp compiles ^ \\b \\B as
    /// start-only lookbehinds; Vectorscan rejects embedded anchors and UCP \\b).
    assertions: Assertions = .{},
    /// Lookaheads (and `$` under m) allowed inside quantifiers that can repeat, max >= 2 (resharp: no).
    lookahead_in_star: bool = true,
    /// Lookbehind bodies may not hold an unbounded quantifier over anything but a single
    /// consuming atom (Java: "Look-behind group does not have an obvious maximum length").
    lookbehind_no_unbounded_group: bool = false,
    /// Lookbehind bodies may not hold variable quantifiers (min != max) or lookaheads (Onigmo).
    lookbehind_no_variable: bool = false,
    /// A quantifier body may be a bare assertion or an alternation offering one, e.g.
    /// (?:a|\b)+ (Oniguruma: "target of repeat operator is invalid").
    quantify_assertions: bool = true,
    /// Oniguruma lookbehind: no lookarounds or quantified captures inside, and no captures
    /// inside a negative lookbehind ("invalid pattern in look-behind").
    lookbehind_onig: bool = false,
    /// No `??`, `*?`, `+?` inside lookbehind (ICU; `{m,n}?` compiles).
    lookbehind_no_lazy: bool = false,
    /// No quantifier at all inside lookbehind (Boost).
    lookbehind_no_quant: bool = false,
    /// Which match an unanchored search reports: the first in backtracking priority order
    /// (Perl, JS, Java, ...) or the leftmost-longest (POSIX).
    span_semantics: SpanSemantics = .first,
    /// After a loop iteration that matched empty (once min is met): ES rejects that path;
    /// Perl/PCRE accept it and leave the loop.
    empty_iteration: EmptyIteration = .reject,
    /// When a pattern has named groups, plain `(...)` groups don't capture (Ruby, Oniguruma).
    named_groups_only: bool = false,
    /// Counted quantifiers are always greedy: the host prints `{m,n}` without the lazy `?`
    /// (Emacs reads `\\{m,n\\}?` as "optional"), so span checks treat them as greedy.
    lazy_counted_is_greedy: bool = false,
    /// `{n}?` means `(?:{n})?` (Ruby syntax), so a lazy exact count prints as `{n}`.
    lazy_exact_is_optional: bool = false,
    /// Extra ASCII metacharacters, printed as code-point escapes (resharp: _ & ~).
    extra_meta: []const u8 = "",
    allow_lazy: bool = true,
    /// Quantifiers over bodies that can only match the empty string, e.g. (?:)* or (?:\\b)*.
    allow_empty_quant: bool = true,
    /// Only `?` may quantify a body that can match empty (Racket).
    nullable_quant_opt_only: bool = false,
    /// Pool characters to drop (e.g. multi-character case folds).
    pool_exclude: []const u21 = &.{},
    /// Byte-oriented engine modelled on ASCII only: non-ASCII leaves the pool and the
    /// self-check skips non-ASCII subjects (LLVM Regex).
    ascii_only: bool = false,
    /// Lookbehind bodies must have a provably bounded length (< cap); 0 = no limit.
    lookbehind_len_cap: u16 = 0,
    /// Lookbehind bodies must have a fixed length (min == max); implies a cap.
    lookbehind_fixed: bool = false,
};

pub const es = @import("dialects/es.zig").dialect;
pub const cpp = @import("dialects/es.zig").cpp;
pub const irregexp = @import("dialects/es.zig").irregexp;
pub const perl = @import("dialects/perl.zig").dialect;
pub const pcre2 = @import("dialects/perl.zig").pcre2;
pub const perl_a = @import("dialects/perl.zig").perl_a;
pub const perl_aa = @import("dialects/perl.zig").perl_aa;
pub const pcre2_ascii = @import("dialects/perl.zig").pcre2_ascii;
pub const boost = @import("dialects/perl.zig").boost;
pub const pcre1 = @import("dialects/perl.zig").pcre1;
pub const swift = @import("dialects/swift.zig").dialect;
pub const rust = @import("dialects/rust.zig").dialect;
pub const fancy = @import("dialects/rust.zig").fancy;
pub const rust_lite = @import("dialects/rust.zig").lite;
pub const re2 = @import("dialects/re2.zig").dialect;
pub const go = @import("dialects/re2.zig").go;
pub const re2_longest = @import("dialects/re2.zig").re2_longest;
pub const go_longest = @import("dialects/re2.zig").go_longest;
pub const re2j = @import("dialects/re2.zig").re2j;
pub const python = @import("dialects/python.zig").dialect;
pub const python_regex = @import("dialects/python.zig").regex_module;
pub const java = @import("dialects/java.zig").dialect;
pub const java_ascii = @import("dialects/java.zig").ascii;
pub const ruby = @import("dialects/ruby.zig").dialect;
pub const oniguruma = @import("dialects/ruby.zig").oniguruma;
pub const onig_perl = @import("dialects/ruby.zig").onig_perl;
pub const onig_java = @import("dialects/ruby.zig").onig_java;
pub const onig_python = @import("dialects/ruby.zig").onig_python;
pub const onig_ascii = @import("dialects/ruby.zig").onig_ascii;
pub const dotnet = @import("dialects/dotnet.zig").dialect;
pub const dotnet_nb = @import("dialects/dotnet.zig").nonbacktracking;
pub const dotnet_compiled = @import("dialects/dotnet.zig").compiled;
pub const dotnet_ecma = @import("dialects/dotnet.zig").ecma;
pub const icu = @import("dialects/icu.zig").dialect;
pub const resharp = @import("dialects/resharp.zig").dialect;
pub const nim = @import("dialects/nim.zig").dialect;
pub const racket = @import("dialects/racket.zig").dialect;
pub const tcl = @import("dialects/tcl.zig").dialect;
pub const emacs = @import("dialects/emacs.zig").dialect;
pub const vectorscan = @import("dialects/vectorscan.zig").dialect;
pub const llvm = @import("dialects/llvm.zig").dialect;
pub const libc = @import("dialects/llvm.zig").libc;
pub const gnu = @import("dialects/llvm.zig").gnu;
pub const all = [_]*const Dialect{ &es, &irregexp, &perl, &pcre2, &perl_a, &perl_aa, &pcre2_ascii, &swift, &rust, &rust_lite, &fancy, &re2, &go, &re2_longest, &go_longest, &python, &python_regex, &java, &java_ascii, &ruby, &oniguruma, &dotnet, &dotnet_nb, &dotnet_compiled, &icu, &resharp, &nim, &racket, &tcl, &emacs, &vectorscan, &llvm, &libc, &cpp, &boost, &re2j, &onig_perl, &onig_java, &onig_python, &onig_ascii, &dotnet_ecma, &pcre1, &gnu };

/// The active dialect (process-wide; chosen once at startup).
pub var active: *const Dialect = &es;

pub fn byName(name: []const u8) ?*const Dialect {
    for (all) |d| if (std.mem.eql(u8, d.name, name)) return d;
    if (std.mem.eql(u8, name, "js")) return &es;
    return null;
}

pub fn isEs() bool {
    return active == &es;
}

/// Strings decode to code points only (no lone surrogates on the wire).
pub fn codePointsOnly() bool {
    return active.strings == .code_points;
}

/// Length bounds of a subtree: (min, max) symbols, saturating at `cap`.
/// Subtree length bounds; `la`: contains a lookahead or `$` (no flags here, so conservative).
pub const Assertions = packed struct {
    caret: bool = true,
    dollar: bool = true,
    wordb: bool = true,
    nwordb: bool = true,

    pub fn allows(self: Assertions, kind: anytype) bool {
        return switch (kind) {
            .caret => self.caret,
            .dollar => self.dollar,
            .wordb => self.wordb,
            .nwordb => self.nwordb,
            else => true,
        };
    }
};

/// Properties under case-insensitive matching (checked by the startup self-check):
/// equivalence: case equivalence like any set, \P complemented before folding (ES);
/// equivalence_invert: the same for \p, \P is the inverse after folding (Java, ICU, Onigmo,
/// Rust, RE2, Go); cased: Lu/Ll mean any cased letter (Perl, PCRE); plain: /i ignored
/// (Oniguruma, Vectorscan, nim); upper_lower: c, its simple upper or lower form (.NET).
pub const PropCase = enum { equivalence, equivalence_invert, cased, plain, upper_lower };

pub const SpanSemantics = enum { first, longest };
/// `unmodeled`: the engine's rule is implementation-specific (automata engines: RE2, Go,
/// Rust); span checks skip patterns where a quantified body can match empty.
pub const EmptyIteration = enum { reject, stop, unmodeled };

pub const Len = struct { min: u32, max: u32, f: u32 = 0 };
pub const len_cap_default: u32 = 16;

/// Does a tree respect the active dialect's grammar restrictions? (Used by the
/// shrinker so candidates stay inside the grammar the tables generate; mirrors
/// table.zig's applyUnary/applyBinary.)
pub fn treeAllowed(t: anytype) bool {
    var ok = true;
    _ = lenOf(t, t.root, &ok);
    return ok;
}

fn lenOf(t: anytype, idx: u8, ok: *bool) Len {
    const ast = @import("ast.zig");
    const tb = @import("table.zig");
    const inherit = tb.aux_inherit;
    const n = t.nodes[idx];
    const cap = len_cap_default;
    const d = active;
    switch (n.op) {
        .atom => {
            if (!d.assertions.allows(n.atom.kind)) ok.* = false;
            const k = n.atom.kind;
            var f: u32 = 0;
            if (k == .dollar) f |= tb.aux_md;
            if (k == .caret or k == .dollar or k == .wordb or k == .nwordb) f |= tb.aux_za;
            if (k == .grapheme) return .{ .min = 1, .max = cap, .f = tb.aux_gx };
            if (n.atom.isConsuming()) return .{ .min = n.atom.minLen(), .max = n.atom.maxLen(), .f = tb.aux_atom };
            return .{ .min = 0, .max = 0, .f = f };
        },
        .concat => {
            const a = lenOf(t, n.a, ok);
            const b = lenOf(t, n.b, ok);
            return .{ .min = @min(cap, a.min + b.min), .max = @min(cap, a.max + b.max), .f = (a.f | b.f) & inherit };
        },
        .alt => {
            const a = lenOf(t, n.a, ok);
            const b = lenOf(t, n.b, ok);
            return .{ .min = @min(a.min, b.min), .max = @max(a.max, b.max), .f = ((a.f | b.f) & (inherit | tb.aux_za)) | tb.aux_cx };
        },
        .quant => {
            const c = lenOf(t, n.a, ok);
            const q = n.quant;
            if (q.lazy and !d.allow_lazy) ok.* = false;
            if (!d.allow_empty_quant and c.max == 0) ok.* = false;
            if (d.nullable_quant_opt_only and c.min == 0 and q.form != .opt) ok.* = false;
            if (!d.lookahead_in_star and c.f & (tb.aux_la | tb.aux_md) != 0 and q.max >= 2) ok.* = false;
            if (!d.quantify_assertions and c.f & tb.aux_za != 0) ok.* = false;
            if (!d.counted_lookaround and c.f & tb.aux_lk != 0 and !(q.form == .star or q.form == .plus or q.form == .opt)) ok.* = false;
            const f = tb.quantFlags(c.f, q.min, q.max, ast.inf, q.lazy, q.min == 0 and q.max == 1, q.form == .star or q.form == .plus or q.form == .opt, false);
            return .{ .min = @min(cap, c.min * q.min), .max = if (q.max == ast.inf) cap else @min(cap, c.max * q.max), .f = f };
        },
        .look_ahead, .neg_look_ahead => {
            const c = lenOf(t, n.a, ok);
            if (!d.allow_lookahead) ok.* = false;
            return .{ .min = 0, .max = 0, .f = tb.aux_la | tb.aux_lk | tb.aux_za | (c.f & inherit) };
        },
        .look_behind, .neg_look_behind => {
            // \X never goes inside lookbehind (no engine matches it right to left the same way).
            if (lenOf(t, n.a, ok).f & tb.aux_gx != 0) ok.* = false;
            const c = lenOf(t, n.a, ok);
            if (!d.allow_lookbehind) ok.* = false;
            if (d.lookbehind_len_cap > 0 and c.max >= d.lookbehind_len_cap) ok.* = false;
            if (d.lookbehind_fixed and (c.min != c.max or c.max >= cap)) ok.* = false;
            if (d.lookbehind_no_unbounded_group and c.f & tb.aux_uq != 0) ok.* = false;
            if (d.lookbehind_no_variable and c.f & (tb.aux_vq | tb.aux_la) != 0) ok.* = false;
            if (d.lookbehind_no_quant and c.f & tb.aux_q != 0) ok.* = false;
            if (d.lookbehind_onig and (c.f & (tb.aux_lk | tb.aux_cq) != 0 or (n.op == .neg_look_behind and c.f & tb.aux_cp != 0))) ok.* = false;
            if (d.lookbehind_no_lazy and c.f & tb.aux_lz != 0) ok.* = false;
            return .{ .min = 0, .max = 0, .f = tb.aux_lk | tb.aux_za | (c.f & inherit) };
        },
        .group_nc => return lenOf(t, n.a, ok),
        .flag_group => {
            const c = lenOf(t, n.a, ok);
            return .{ .min = c.min, .max = c.max, .f = c.f & ~tb.aux_atom };
        },
        .group_cap, .group_named => {
            const c = lenOf(t, n.a, ok);
            return .{ .min = c.min, .max = c.max, .f = (c.f & inherit) | tb.aux_cp };
        },
        .atomic => {
            if (!d.atomic_groups) ok.* = false;
            const c = lenOf(t, n.a, ok);
            return .{ .min = c.min, .max = c.max, .f = (c.f & inherit) | tb.aux_cx };
        },
        // A backreference's length is the group's: variable, so lookbehind rules reject it.
        .backref => {
            if (!d.backrefs) ok.* = false;
            return .{ .min = 0, .max = cap, .f = tb.aux_vq | tb.aux_uq | tb.aux_cx };
        },
    }
}

/// Subjects never contain lone surrogates for this dialect.
pub fn noLoneSurrogates() bool {
    return active.strings != .es;
}

/// PCRE2's \h: tab, space, NBSP, U+1680, U+180E, U+2000..U+200A, U+202F, U+205F, U+3000.
pub fn defaultHSpace(c: u21) bool {
    return c == 0x09 or c == 0x20 or c == 0xA0 or c == 0x1680 or c == 0x180E or (c >= 0x2000 and c <= 0x200A) or c == 0x202F or c == 0x205F or c == 0x3000;
}
/// PCRE2's \v: \n, VT, FF, \r, NEL, LS, PS.
pub fn defaultVSpace(c: u21) bool {
    return (c >= 0x0A and c <= 0x0D) or c == 0x85 or c == 0x2028 or c == 0x2029;
}

/// The pool without the dialect's pattern-only characters (for drawing subjects).
pub fn subjectPool(pool: []const u21, buf: []u21) []const u21 {
    if (active.pattern_only.len == 0) return pool;
    var n: usize = 0;
    for (pool) |c| if (std.mem.indexOfScalar(u21, active.pattern_only, c) == null) {
        buf[n] = c;
        n += 1;
    };
    return if (n == 0) pool else buf[0..n];
}
