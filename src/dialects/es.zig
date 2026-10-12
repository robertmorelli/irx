//! ECMAScript 2024 (exact model; reference engine d8).
const alpha = @import("../alphabet.zig");
const D = @import("../dialect.zig");

pub const dialect: D.Dialect = .{
    .scoped_flags = true,
    .unicode_props = true,
    .props_need_u = true,
    .name = "es",
    .isLineTerminator = alpha.esLineTerminator,
    .isSpace = alpha.esSpace,
    .isWord = alpha.esWordChar,
    .isDigit = alpha.isDigit,
};
