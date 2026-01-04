//! x86fmt core module
//!
//! For general formatting purposes, simply use Fmt.

/// The core formatter
pub const Fmt = @import("fmt.zig");

/// Runtime settings for Fmt
pub const Settings = @import("fmt_settings.zig");

pub const Token = @import("fmt_token.zig");
pub const Lexeme = @import("fmt_lexeme.zig");
pub const Line = @import("fmt_line.zig");

test "Module" {
    _ = @import("fmt.zig");
    _ = @import("fmt_settings.zig");
    _ = @import("fmt_token.zig");
    _ = @import("fmt_lexeme.zig");
    _ = @import("fmt_line.zig");
}
