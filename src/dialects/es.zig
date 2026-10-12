//! ECMAScript 2024 (exact model; reference engine d8).
const alpha = @import("../alphabet.zig");
const D = @import("../dialect.zig");

pub const dialect: D.Dialect = .{
    .backrefs = true,
    .backref_unset_matches_empty = true,
    .scoped_flags = true,
    .unicode_props = true,
    .props_need_u = true,
    .duplicate_names = true,
    .name = "es",
    .isLineTerminator = alpha.esLineTerminator,
    .isSpace = alpha.esSpace,
    .isWord = alpha.esWordChar,
    .isDigit = alpha.isDigit,
};

/// V8 and SpiderMonkey (Irregexp): ES, except that \q{…} strings under i are compared case-
/// sensitively against the folded string (IRX-V8-5), so no \q is generated under i.
pub const irregexp: D.Dialect = blk: {
    var d = dialect;
    d.name = "irregexp";
    d.qstr_ignore_case = false;
    break :blk d;
};

/// C++ std::regex (libc++, ECMAScript grammar) over code points: no lookbehind, no inline
/// modifiers, no \p; the pool stays ASCII (its classes and case folding use the C locale).
pub const cpp: D.Dialect = blk: {
    var d = dialect;
    d.name = "cpp";
    d.allow_lookbehind = false;
    d.scoped_flags = false;
    d.unicode_props = false;
    d.ascii_only = true;
    // ES3-era grammar: no named groups, no \u{…}; code points are written \x{H}, which the
    // host turns into literal characters.
    d.named_group = .plain_capture;
    d.escape = .x_brace;
    // multiline ^ does not match at the very end after a trailing line terminator.
    d.caret_after_trailing_newline = false;
    // libc++'s loop over a body that matched empty follows its own rule; spans skip such patterns.
    d.empty_iteration = .unmodeled;
    // A reference to a group that did not participate fails (IRX-LIBCXX-4; ES says empty).
    d.backref_unset_matches_empty = false;
    d.duplicate_names = false;
    break :blk d;
};
