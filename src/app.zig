const std = @import("std");
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const assert = std.debug.assert;

const AppSettings = @import("app_settings.zig");

// TODO: use exported module internally too (conflict with utl_branchless being shared)
const x86fmt = @import("root.zig");
const Formatter = x86fmt.Fmt.Formatter;

const BLAND = @import("utl_branchless.zig").BLAND;

// FIXME: BUF_SIZE_LINE_IO affects whether tests pass.
//  - when set to 4096, long tests mismatch at around byte 4080; when set to 8096,
//    mismatch is at over 8000 bytes in.
//  - it seems the other buffer sizes are not affecting this, only BUF_SIZE_LINE_IO.
//  - tests pass when set to 16096.
//  - Formatter itself doesn't use BUF_SIZE_LINE_IO at all, so it must be an error
//    in this file? or, a problem with writer usage in fmt?
//  - problem happens when formatting the test file directly with the built app,
//    not only when running tests, i.e. it isn't the test code
const BUF_SIZE_LINE_IO = 4096; // NOTE: meant to be 4095; std bug in Reader.readUntilDelimiterOrEof
const BUF_SIZE_LINE_TOK = 1024;
const BUF_SIZE_LINE_LEX = 512;
const BUF_SIZE_TOK = 256;

var STDI_BUF = std.mem.zeroes([BUF_SIZE_LINE_IO]u8);
var STDO_BUF = std.mem.zeroes([BUF_SIZE_LINE_IO]u8);
var STDE_BUF = std.mem.zeroes([BUF_SIZE_LINE_IO]u8);

/// @args   *ArgIterator or *ArgIteratorGeneral from std.process
///         assumes argument containing executable name is already skipped
/// @stdi   stdin File
/// @stdo   stdout File
/// @stde   stderr File
pub fn Main(alloc: Allocator, args: anytype, stdi: File, stdo: File, stde: File) !void {
    var settings = AppSettings.ParseCLI(alloc, args) catch |err| {
        var w = stde.writer(&STDE_BUF);
        defer w.interface.flush() catch {};
        try w.interface.print("Settings Error ({s})", .{@errorName(err)});
        return;
    };
    defer settings.Deinit(alloc);

    if (settings.bShowHelp) {
        var w = stdo.writer(&STDO_BUF);
        defer w.interface.flush() catch {};
        _ = try w.interface.write(AppSettings.HelpText);
        return;
    }

    {
        const fi = switch (settings.IKind) {
            .File => try std.fs.cwd().openFile(settings.IFile, .{}),
            .Console => c: {
                if (BLAND(!settings.bAllowTty, stdi.isTty())) {
                    var w = stdo.writer(&STDO_BUF);
                    defer w.interface.flush() catch {};
                    _ = try w.interface.write(AppSettings.HelpTextShort);
                    return;
                }
                break :c stdi;
            },
        };
        defer if (settings.IKind == .File) fi.close();
        var br = fi.reader(&STDI_BUF);

        const fo = switch (settings.OKind) {
            .File => try std.fs.cwd().createFile(settings.OFile, .{}),
            .Console => stdo,
        };
        defer if (settings.OKind == .File) fo.close();
        var bw = fo.writer(&STDO_BUF);
        defer bw.interface.flush() catch {};

        var bew = stde.writer(&STDE_BUF);
        defer bew.interface.flush() catch {};

        const fmt = Formatter(BUF_SIZE_LINE_IO, BUF_SIZE_LINE_TOK, BUF_SIZE_LINE_LEX, BUF_SIZE_TOK);
        fmt.Format(&br.interface, &bw.interface, &bew.interface, settings.Format) catch |err| {
            try bew.interface.print("Formatting Error ({s})", .{@errorName(err)});
        };
    }

    if (settings.bIOFileSame)
        try std.fs.cwd().rename(settings.OFile, settings.IFile);
}

// TESTING

// TODO: assign temp dir and alloc filenames within each loop?
// TODO: test tty, somehow
// TODO: stderr tests
test "App Main" {
    std.testing.log_level = .debug;
    const error_file = "stderr_dump.txt";

    const TestCase = struct {
        const TestCaseIO = enum { File, Console };

        cmd: []const u8,
        in_data: []const u8,
        ex_data: []const u8,
        in: TestCaseIO = .Console,
        out: TestCaseIO = .Console,
        input_is_expected_output: bool = false,
        //tty: bool = false,
    };

    const input_file = "input.s";
    const output_file_disk = "output.s";
    const output_file_buf = "output_buf.s";
    const testfile_app_base = @embedFile("testfile_app_base");
    const testfile_app_default = @embedFile("testfile_app_default");
    const testfile_app_all = @embedFile("testfile_app_all");
    const all_args = "-ts 2 -mbl 1 -tcc 36 -tia 8 -toa 6 -dcc 72 -dia 20" ++
        " -doa 36 -sin 2 -sid 4 -sit 6 -sio 8";

    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var tmpdir = std.testing.tmpDir(.{});
    defer tmpdir.cleanup();
    const tmpdir_path = try tmpdir.dir.realpathAlloc(arena_alloc, "");

    const test_cases = [_]TestCase{
        // default formatting
        .{
            // stdin -> stdout
            .cmd = "",
            .in_data = testfile_app_base,
            .ex_data = testfile_app_default,
        },
        .{
            // stdin -> file
            .cmd = try std.fmt.allocPrint(arena_alloc, "-fo {s}/{s}", .{ tmpdir_path, output_file_disk }),
            .in_data = testfile_app_base,
            .ex_data = testfile_app_default,
            .out = .File,
        },
        .{
            // file -> stdout
            .cmd = try std.fmt.allocPrint(arena_alloc, "{s}/{s} -co", .{ tmpdir_path, input_file }),
            .in_data = testfile_app_base,
            .ex_data = testfile_app_default,
            .in = .File,
        },
        .{
            // file1 -> file1
            .cmd = try std.fmt.allocPrint(arena_alloc, "{s}/{s}", .{ tmpdir_path, input_file }),
            .in_data = testfile_app_base,
            .ex_data = testfile_app_default,
            .input_is_expected_output = true,
            .in = .File,
            .out = .File,
        },
        .{
            // file1 -> file1 (explicit)
            .cmd = try std.fmt.allocPrint(
                arena_alloc,
                "{s}/{s} -fo {s}/{s}",
                .{ tmpdir_path, input_file, tmpdir_path, input_file },
            ),
            .in_data = testfile_app_base,
            .ex_data = testfile_app_default,
            .input_is_expected_output = true,
            .in = .File,
            .out = .File,
        },
        .{
            // file1 -> file2
            .cmd = try std.fmt.allocPrint(
                arena_alloc,
                "{s}/{s} -fo {s}/{s}",
                .{ tmpdir_path, input_file, tmpdir_path, output_file_disk },
            ),
            .in_data = testfile_app_base,
            .ex_data = testfile_app_default,
            .in = .File,
            .out = .File,
        },
        // 'all' formatting
        .{
            // stdin -> stdout
            .cmd = try std.fmt.allocPrint(arena_alloc, "{s}", .{all_args}),
            .in_data = testfile_app_base,
            .ex_data = testfile_app_all,
        },
        .{
            // stdin -> file
            .cmd = try std.fmt.allocPrint(
                arena_alloc,
                "-fo {s}/{s} {s}",
                .{ tmpdir_path, output_file_disk, all_args },
            ),
            .in_data = testfile_app_base,
            .ex_data = testfile_app_all,
            .out = .File,
        },
        .{
            // file -> stdout
            .cmd = try std.fmt.allocPrint(
                arena_alloc,
                "{s}/{s} -co {s}",
                .{ tmpdir_path, input_file, all_args },
            ),
            .in_data = testfile_app_base,
            .ex_data = testfile_app_all,
            .in = .File,
        },
        .{
            // file1 -> file1
            .cmd = try std.fmt.allocPrint(
                arena_alloc,
                "{s}/{s} {s}",
                .{ tmpdir_path, input_file, all_args },
            ),
            .in_data = testfile_app_base,
            .ex_data = testfile_app_all,
            .input_is_expected_output = true,
            .in = .File,
            .out = .File,
        },
        .{
            // file1 -> file1 (explicit)
            .cmd = try std.fmt.allocPrint(
                arena_alloc,
                "{s}/{s} -fo {s}/{s} {s}",
                .{ tmpdir_path, input_file, tmpdir_path, input_file, all_args },
            ),
            .in_data = testfile_app_base,
            .ex_data = testfile_app_all,
            .input_is_expected_output = true,
            .in = .File,
            .out = .File,
        },
        .{
            // file1 -> file2
            .cmd = try std.fmt.allocPrint(
                arena_alloc,
                "{s}/{s} -fo {s}/{s} {s}",
                .{ tmpdir_path, input_file, tmpdir_path, output_file_disk, all_args },
            ),
            .in_data = testfile_app_base,
            .ex_data = testfile_app_all,
            .in = .File,
            .out = .File,
        },
    };

    var loop_arena = std.heap.ArenaAllocator.init(arena_alloc);
    defer loop_arena.deinit();
    const loop_arena_alloc = arena.allocator();

    inline for (test_cases, 0..) |t, i| {
        errdefer std.debug.print("FAILED {d:0>2} :: {s}\n\n", .{ i, t.cmd });
        defer _ = loop_arena.reset(.retain_capacity);
        defer tmpdir.dir.deleteFile(error_file) catch {};
        defer tmpdir.dir.deleteFile(input_file) catch {};
        defer tmpdir.dir.deleteFile(output_file_buf) catch {};
        defer tmpdir.dir.deleteFile(output_file_disk) catch {};

        {
            const input = blk: {
                // Main takes Files as input, so we have to copy the data to an
                // actual file for it to act as a buffer (regardless of whether
                // Main thinks it's acting on a disk or std handle).
                const f = try tmpdir.dir.createFile(input_file, .{});
                try f.writeAll(t.in_data);
                f.close();
                break :blk switch (t.in) {
                    // FIXME: thought you can do tty tests with `.allow_ctty = true`
                    //  here, but it seems not; need to figure out how
                    .Console => try tmpdir.dir.openFile(input_file, .{}),
                    .File => std.fs.File.stdin(), // dummy File
                };
            };
            defer if (t.in == .Console) input.close();

            const output = switch (t.out) {
                .Console => try tmpdir.dir.createFile(output_file_buf, .{}),
                .File => std.fs.File.stdout(), // dummy File
            };
            defer if (t.out == .Console) output.close();

            const stde = try tmpdir.dir.createFile(error_file, .{});
            defer stde.close();

            var args = try std.process.ArgIteratorGeneral(.{}).init(loop_arena_alloc, t.cmd);

            try Main(loop_arena_alloc, &args, input, output, stde);
        }

        const output_buf = blk: {
            const ex_filename = if (t.input_is_expected_output) input_file else switch (t.out) {
                .Console => output_file_buf,
                .File => output_file_disk,
            };
            const f = try tmpdir.dir.openFile(ex_filename, .{});
            defer f.close();
            break :blk try f.readToEndAlloc(loop_arena_alloc, std.math.maxInt(usize));
        };

        //try std.testing.expectEqualSlices(u8, t.ex_data, output_buf);
        try std.testing.expectEqualStrings(t.ex_data, output_buf);
        try std.testing.expectEqual(t.ex_data.len, output_buf.len);
    }
}
