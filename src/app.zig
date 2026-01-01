const std = @import("std");
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const assert = std.debug.assert;

const AppSettings = @import("app_settings.zig");
const Formatter = @import("fmt.zig").Formatter;
const BLAND = @import("utl_branchless.zig").BLAND;

const BUF_SIZE_LINE_IO = 4096; // NOTE: meant to be 4095; std bug in Reader.readUntilDelimiterOrEof
const BUF_SIZE_LINE_TOK = 1024;
const BUF_SIZE_LINE_LEX = 512;
const BUF_SIZE_TOK = 256;

/// @args   *ArgIterator or *ArgIteratorGeneral from std.process
///         assumes argument containing executable name is already skipped
/// @stdi   stdin File
/// @stdo   stdout File
pub fn Main(alloc: Allocator, args: anytype, stdi: File, stdo: File, stde: File) !void {
    var settings = AppSettings.ParseCLI(alloc, args) catch |err| {
        try stde.writer().print("Settings Error ({s})", .{@errorName(err)});
        return;
    };
    defer settings.Deinit(alloc);

    if (settings.bShowHelp) {
        _ = try stdo.writer().write(AppSettings.HelpText);
        return;
    }

    {
        const fi = switch (settings.IKind) {
            .File => try std.fs.cwd().openFile(settings.IFile, .{}),
            .Console => c: {
                if (BLAND(!settings.bAllowTty, stdi.isTty())) {
                    _ = try stdo.writer().write(AppSettings.HelpTextShort);
                    return;
                }
                break :c stdi;
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

        var bew = std.io.bufferedWriter(stde.writer());
        defer bew.flush() catch {};

        const fmt = Formatter(BUF_SIZE_LINE_IO, BUF_SIZE_LINE_TOK, BUF_SIZE_LINE_LEX, BUF_SIZE_TOK);
        fmt.Format(br.reader(), bw.writer(), bew.writer(), settings.Format) catch |err| {
            try stde.writer().print("Formatting Error ({s})", .{@errorName(err)});
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
        const TestCaseIO = enum { file, console };

        cmd: []const u8,
        in_data: []const u8,
        ex_data: []const u8,
        in: TestCaseIO = .console,
        out: TestCaseIO = .console,
        use_input_for_expected: bool = false,
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
            .out = .file,
        },
        .{
            // file -> stdout
            .cmd = try std.fmt.allocPrint(arena_alloc, "{s}/{s} -co", .{ tmpdir_path, input_file }),
            .in_data = testfile_app_base,
            .ex_data = testfile_app_default,
            .in = .file,
        },
        .{
            // file1 -> file1
            .cmd = try std.fmt.allocPrint(arena_alloc, "{s}/{s}", .{ tmpdir_path, input_file }),
            .in_data = testfile_app_base,
            .ex_data = testfile_app_default,
            .use_input_for_expected = true,
            .in = .file,
            .out = .file,
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
            .use_input_for_expected = true,
            .in = .file,
            .out = .file,
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
            .in = .file,
            .out = .file,
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
            .out = .file,
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
            .in = .file,
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
            .use_input_for_expected = true,
            .in = .file,
            .out = .file,
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
            .use_input_for_expected = true,
            .in = .file,
            .out = .file,
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
            .in = .file,
            .out = .file,
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
                    .console => try tmpdir.dir.openFile(input_file, .{}),
                    .file => std.io.getStdIn(), // dummy File
                };
            };
            defer if (t.in == .console) input.close();

            const output = switch (t.out) {
                .console => try tmpdir.dir.createFile(output_file_buf, .{}),
                .file => std.io.getStdOut(), // dummy File
            };
            defer if (t.out == .console) output.close();

            const stde = try tmpdir.dir.createFile(error_file, .{});
            defer stde.close();

            var args = try std.process.ArgIteratorGeneral(.{}).init(loop_arena_alloc, t.cmd);

            try Main(loop_arena_alloc, &args, input, output, stde);
        }

        const output_buf = blk: {
            const ex_filename = if (t.use_input_for_expected) input_file else switch (t.out) {
                .console => output_file_buf,
                .file => output_file_disk,
            };
            const f = try tmpdir.dir.openFile(ex_filename, .{});
            defer f.close();
            break :blk try f.readToEndAlloc(loop_arena_alloc, std.math.maxInt(usize));
        };

        try std.testing.expectEqualStrings(t.ex_data, output_buf);
    }
}
