const std = @import("std");
const Allocator = std.mem.Allocator;

const App = @import("app.zig");

var mem: [4096]u8 = undefined;

// FIXME: add tests for app itself (via separate build step that runs the program
//  with different intputs), testing different i/o configurations and cli opts
pub fn main() !void {
    var fba = std.heap.FixedBufferAllocator.init(&mem);
    const alloc = fba.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.next();

    const stdi = std.io.getStdIn();
    const stdo = std.io.getStdOut();

    return App.Main(alloc, &args, stdi, stdo);
}

test {
    _ = @import("app.zig");
    _ = @import("app_settings.zig");
    _ = @import("fmt.zig");
    _ = @import("fmt_token.zig");
    _ = @import("fmt_lexeme.zig");
    _ = @import("fmt_line.zig");
    _ = @import("utl_branchless.zig");
    _ = @import("utl_cli.zig");
    _ = @import("utl_utf8_line_measuring_writer.zig");
}
