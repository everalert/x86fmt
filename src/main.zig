//! x86fmt executable

const std = @import("std");
const Allocator = std.mem.Allocator;

const App = @import("app.zig");

// TODO: make app actually only use this; eradicate other static memory
// from codebase
/// 256KiB
/// Fits within L2 cache on everything Intel Core i 10th gen onward, including
/// AMD chips from the same period. Change to 512KiB for Core i 11th gen onward.
const MEMORY_SIZE = 0x1000 * 256;
var MEMORY: [MEMORY_SIZE]u8 = undefined;

pub fn main() !void {
    var fba = std.heap.FixedBufferAllocator.init(&MEMORY);
    const alloc = fba.allocator();

    var args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const stdi = std.fs.File.stdin();
    const stdo = std.fs.File.stdout();
    const stde = std.fs.File.stderr();

    return App.Main(alloc, args[1..], stdi, stdo, stde);
}

test "Application" {
    _ = @import("app.zig");
    _ = @import("app_settings.zig");
    _ = @import("app_version.zig");
    _ = @import("app_manifest.zig");
}
