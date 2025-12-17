const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const CLI = @import("cli.zig");
const Format = @import("format.zig");

var mem: [4096]u8 = undefined;

// FIXME: add tests for app itself (via separate build step that runs the program
//  with different intputs), testing different i/o configurations and cli opts
pub fn main() !void {
    var fba = std.heap.FixedBufferAllocator.init(&mem);
    const alloc = fba.allocator();
    const cli = try CLI.Parse(alloc); // FIXME: handle

    if (cli.bShowHelp) {
        var stdo = std.io.getStdOut();
        _ = try stdo.write("x86fmt help\n\n\tHelp text not written yet, sorry...\n\n");
        return;
    }

    const fi = switch (cli.IKind) {
        .File => try std.fs.cwd().openFile(cli.IFile, .{}),
        .Console => std.io.getStdIn(),
    };
    const fo = switch (cli.OKind) {
        .File => try std.fs.cwd().createFile(cli.OFile, .{}),
        .Console => std.io.getStdOut(),
    };
    var br = std.io.bufferedReader(fi.reader());
    var bw = std.io.bufferedWriter(fo.writer());

    try Format.Format(br.reader(), bw.writer(), .{}); // FIXME: handle

    bw.flush() catch unreachable; // FIXME: handle
    fo.close();
    fi.close();

    if (cli.bIOFileSame) {
        try std.fs.cwd().deleteFile(cli.IFile);
        try std.fs.cwd().rename(cli.OFile, cli.IFile);
    }
}

test {
    _ = @import("format.zig");
}
