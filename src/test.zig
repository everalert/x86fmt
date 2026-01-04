//! x86fmt tests
//!
//! Holistically tests the entire codebase. For module-specific tests, see
//! `main.zig` and `root.zig`.

test {
    _ = @import("main.zig");
    _ = @import("root.zig");
    _ = @import("utl_branchless.zig");
    _ = @import("utl_cli.zig");
    _ = @import("utl_utf8_line_measuring_writer.zig");
}
