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

    const stdi = std.fs.File.stdin();
    const stdo = std.fs.File.stdout();
    const stde = std.fs.File.stderr();

    return App.Main(alloc, &args, stdi, stdo, stde);
}

test "Application" {
    _ = @import("app.zig");
    _ = @import("app_settings.zig");
    _ = @import("app_version.zig");
    _ = @import("app_manifest.zig");
}
