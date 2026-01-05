//! x86fmt executable

const std = @import("std");
const Allocator = std.mem.Allocator;

const App = @import("app.zig");

var mem: [4096]u8 = undefined;

pub fn main() !void {
    var fba = std.heap.FixedBufferAllocator.init(&mem);
    const alloc = fba.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.next();

    const stdi = std.io.getStdIn();
    const stdo = std.io.getStdOut();
    const stde = std.io.getStdErr();

    return App.Main(alloc, &args, stdi, stdo, stde);
}

test "Application" {
    _ = @import("app.zig");
    _ = @import("app_settings.zig");
}
