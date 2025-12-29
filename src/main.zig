const std = @import("std");
const Allocator = std.mem.Allocator;

const App = @import("app.zig");

var mem: [4096]u8 = undefined;

// FIXME: add tests for app itself (via separate build step that runs the program
//  with different intputs), testing different i/o configurations and cli opts
pub fn main() !void {
    var fba = std.heap.FixedBufferAllocator.init(&mem);
    const alloc = fba.allocator();

    var arg_it = try std.process.argsWithAllocator(alloc);
    defer arg_it.deinit();
    _ = arg_it.next();

    const stdi = std.io.getStdIn();
    const stdo = std.io.getStdOut();

    return App.Main(alloc, &arg_it, stdi, stdo);
}

test {
    _ = @import("app.zig");
    _ = @import("app_settings.zig");
    _ = @import("format.zig");
    _ = @import("token.zig");
    _ = @import("lexeme.zig");
    _ = @import("util.zig");
    _ = @import("utf8_line_measuring_writer.zig");
}
