const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const AppSettings = @import("app_settings.zig");
const Formatter = @import("format.zig").Formatter;
const BLAND = @import("util.zig").BLAND;

const BUF_SIZE_LINE_IO = 4096; // NOTE: meant to be 4095; std bug in Reader.readUntilDelimiterOrEof
const BUF_SIZE_LINE_TOK = 1024;
const BUF_SIZE_LINE_LEX = 512;
const BUF_SIZE_TOK = 256;

// TODO: stderr Writer
/// @args   *ArgIterator or *ArgIteratorGeneral from std.process
///         assumes argument containing executable name is already skipped
/// @stdi   Reader for stdin
/// @stdo   Writer to stdout
pub fn Main(alloc: Allocator, args: anytype, stdi: anytype, stdo: anytype) !void {
    var settings = AppSettings.ParseCLI(alloc, args) catch return;
    defer settings.Deinit(alloc);

    if (settings.bShowHelp) {
        _ = try stdo.write(AppSettings.HelpText);
        return;
    }

    {
        const fi = switch (settings.IKind) {
            .File => try std.fs.cwd().openFile(settings.IFile, .{}),
            .Console => c: {
                const c = stdi;
                if (BLAND(!settings.bAllowTty, c.isTty())) {
                    _ = try stdo.write(AppSettings.HelpTextShort);
                    return;
                }
                break :c c;
            },
        };
        defer if (settings.IKind == .File) fi.close();
        var br = std.io.bufferedReader(fi.reader());

        const fo = switch (settings.OKind) {
            .File => try std.fs.cwd().createFile(settings.OFile, .{}),
            .Console => stdo,
        };
        defer if (settings.OKind == .File) fo.close();
        var bw = std.io.bufferedWriter(fo.writer());
        defer bw.flush() catch {};

        const fmt = Formatter(BUF_SIZE_LINE_IO, BUF_SIZE_LINE_TOK, BUF_SIZE_LINE_LEX, BUF_SIZE_TOK);
        fmt.Format(br.reader(), bw.writer(), settings.Format) catch {};
    }

    if (settings.bIOFileSame)
        try std.fs.cwd().rename(settings.OFile, settings.IFile);
}

// FIXME: add tests
test "App Main" {
    //@compileError("TODO: App Main tests");

    // TODO: tests for each case with both default settings (unchanged input) and
    //  all settings changed. general strategy that avoids "risking" repo test
    //  files may be: @embed both input and output, then for file input case copy
    //  the embedded input to a temp file and delete it (and output file/s) after.
    // TODO: verify correctness of default settings (no cli opts vs explicitly
    //  stating all opts using their default values)
    // TODO: maybe also verify that a "bad" input resultsi in the base case, for
    //  cases that an already-good file wouldn't cover (e.g. removing redundant
    //  whitespace on empty lines, etc.)
    // TODO: file1 -> console
    // TODO: file1 -> file2
    // TODO: file1 -> file1
    // TODO: console -> console
    // TODO: console -> file
}
