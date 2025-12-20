const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const CLI = @import("cli.zig");
const Formatter = @import("format.zig").Formatter;

const BUF_SIZE_LINE_IO = 4095;
const BUF_SIZE_LINE_TOK = 1024;
const BUF_SIZE_LINE_LEX = 512;
const BUF_SIZE_TOK = 256;

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

    {
        const fi = switch (cli.IKind) {
            .File => try std.fs.cwd().openFile(cli.IFile, .{}),
            .Console => c: {
                const c = std.io.getStdIn();
                if (!cli.bAllowTty and c.isTty()) return;
                break :c c;
            },
        };
        defer fi.close();
        var br = std.io.bufferedReader(fi.reader());

        const fo = switch (cli.OKind) {
            .File => try std.fs.cwd().createFile(cli.OFile, .{}),
            .Console => std.io.getStdOut(),
        };
        defer fo.close();
        var bw = std.io.bufferedWriter(fo.writer());
        defer bw.flush() catch unreachable; // FIXME: handle

        const fmt = Formatter(BUF_SIZE_LINE_IO, BUF_SIZE_LINE_TOK, BUF_SIZE_LINE_LEX, BUF_SIZE_TOK);
        try fmt.Format(br.reader(), bw.writer(), cli.FmtSettings); // FIXME: handle
    }

    if (cli.bIOFileSame) {
        try std.fs.cwd().deleteFile(cli.IFile);
        try std.fs.cwd().rename(cli.OFile, cli.IFile);
    }
}

test {
    _ = @import("format.zig");
    _ = @import("util.zig");
}
