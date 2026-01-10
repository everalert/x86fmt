//! Settings for the command line application. Arguments can be provided in any
//! order and will short-circuit if repeated. See HelpText for details on options
//! and usage.
//!
//! Settings provided by this module:
//! - Input mode; defaults to stdin
//! - Output mode; defaults to matching the input setting
//! - Input file; set input to File mode by providing a file path
//! - Output file; will overwrite input file, unless output file specified
//! - Show Help flag
//! - Configuration of formatting values (comment column, etc.)
const AppSettings = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const eql = std.mem.eql;

const StageTwoCheck = @import("utl_cli.zig").StageTwoCheck;
const EnumCheckOnce = @import("utl_cli.zig").EnumCheckOnce;
const BoolCheck = @import("utl_cli.zig").BoolCheck;
const RawCheck = @import("utl_cli.zig").RawCheck;

// TODO: use exported module internally too (conflict with utl_branchless being shared)
const FormatSettings = @import("root.zig").Settings;
const VERSION_STRING = @import("app_version.zig").VERSION_STRING;

// TODO: ?? accept input file without tag only if in first position, and require
//  something like -fi otherwise
// TODO: ?? verify any files here instead of punting
// TODO: ?? return error message instead of ignoring when cli has repeated option;
//  if used as a general rule, this would also mean `x86fmt file -fo file` would
//  error

pub const HelpTextHeader = "x86fmt " ++ VERSION_STRING ++ "\n" ++
    \\https://github.com/everalert/x86fmt
    \\
    \\
;

pub const HelpTextShort = HelpTextHeader ++
    \\  [file]              input mode = File, reading from [file]
    \\  -fo [file]          output mode = File, writing to [file]
    \\  -co                 output mode = Console (stdout)
    \\  -tty, --allow-tty   accept console input for stdin (override this dialog)
    \\
    \\  -h, --help          Show detailed usage information
    \\
    \\
;

pub const HelpText = HelpTextHeader ++
    \\  Freely mix and match file and stdio for input and output. See Sample Usage 
    \\  section for concrete examples.
    \\
    \\  Default behaviour   input mode = Console (stdin)
    \\                      output mode = match input
    \\
    \\Options
    \\
    \\  [file]              input mode = File, reading from [file]
    \\  -fo [file]          output mode = File, writing to [file]
    \\  -co                 output mode = Console (stdout)
    \\  -tty, --allow-tty   accept console input for stdin (default piped input only)
    \\
    \\  -h, --help          Show this dialog without formatting
    \\
    \\Cosmetic Options
    \\  
    \\  -ts [num],  --tab-size [num]                    default 4
    \\  -mbl [num], --max-blank-lines [num]             default 2
    \\  -tcc [num], --text-comment-column [num]         default 40
    \\  -tia [num], --text-instruction-advance [num]    default 12
    \\  -toa [num], --text-operands-advance [num]       default 8
    \\  -dcc [num], --data-comment-column [num]         default 60
    \\  -dia [num], --data-instruction-advance [num]    default 16
    \\  -doa [num], --data-operands-advance [num]       default 32
    \\  -sin [num], --section-indent-none [num]         default 0
    \\  -sid [num], --section-indent-data [num]         default 0
    \\  -sit [num], --section-indent-text [num]         default 0
    \\  -sio [num], --section-indent-other [num]        default 0
    \\
    \\Sample Usage
    \\
    \\  x86fmt (none)                       input: <stdin>    output: <stdout>
    \\  x86fmt source.s                     input: source.s   output: source.s
    \\  x86fmt source.s -co                 input: source.s   output: <stdout>
    \\  x86fmt source.s -fo output.s        input: source.s   output: output.s
    \\  x86fmt -fo output.s                 input: <stdin>    output: output.s
    \\  x86fmt -fo                          (invalid)
    \\  x86fmt source.s -co -ts 2           input: source.s   output: <stdout>   tab size 2
    \\
    \\
;

pub const IOKind = enum { Console, File };

// TODO: ?? RepeatedOption, if going to always show error message on malformed cli
pub const Error = error{ MissingArgumentValue, UnknownFlag };

Format: FormatSettings,
IKind: IOKind,
OKind: IOKind,
IFile: []const u8,
OFile: []const u8,
bAllowTty: bool,
bShowHelp: bool,
/// implies that IKind and OKind are both File. if true, OFile will match IFile
/// but with ".tmp" appended; after formatting, the caller can simply delete
/// IFile and rename OFile in response to this being true.
bIOFileSame: bool,

const def_fmt = FormatSettings.default;

pub const default: AppSettings = .{
    .Format = def_fmt,
    .bAllowTty = false,
    .bShowHelp = false,
    .bIOFileSame = false,
    .IKind = .Console,
    .OKind = .Console,
    .IFile = &.{},
    .OFile = &.{},
};

const Waiters = struct {
    fo: bool,
    ts: bool,
    mbl: bool,
    tcc: bool,
    tia: bool,
    toa: bool,
    dcc: bool,
    dia: bool,
    doa: bool,
    sin: bool,
    sid: bool,
    sit: bool,
    sio: bool,

    pub const default: Waiters = .{
        .fo = false,
        .ts = false,
        .mbl = false,
        .tcc = false,
        .tia = false,
        .toa = false,
        .dcc = false,
        .dia = false,
        .doa = false,
        .sin = false,
        .sid = false,
        .sit = false,
        .sio = false,
    };

    pub fn AnyWaiting(self: *const Waiters) bool {
        var cnt_true: usize = 0;
        inline for (std.meta.fields(Waiters)) |f| {
            comptime assert(f.type == bool);
            cnt_true += @intFromBool(@field(self, f.name));
        }
        return cnt_true > 0;
    }
};

// TODO: maybe just take the whole cli, including exe name, to simplify things
//  so that you don't have to know to skip
/// Parse command line arguments and generate a CLI settings object. Caller is
/// responsible for freeing memory with `Deinit`, and verifying the existence of
/// any files indicated in the return value.
/// @args   *ArgIterator or *ArgIteratorGeneral from std.process
///         assumes argument containing executable name is already skipped
pub fn ParseCLI(alloc: Allocator, args: []const [:0]const u8) !AppSettings {
    var i_kind: ?IOKind = null;
    var o_kind: ?IOKind = null;
    var i_file: []const u8 = &.{};
    var o_file: []const u8 = &.{};
    var b_allow_tty = false;
    var b_show_help = false;
    var b_io_file_same = false;
    var fmt = def_fmt;
    errdefer alloc.free(i_file);
    errdefer alloc.free(o_file);

    var waiters: Waiters = .default;

    //_ = args.next(); // executable location in argv[0] should be skipped before running this
    //while (args.next()) |arg| {
    //for (args[1..]) |arg| {
    for (args) |arg| {
        const fo = EnumCheckOnce(arg, &.{"-fo"}, IOKind, .File, &o_kind);
        if (StageTwoCheck(alloc, arg, fo, []const u8, &o_file, &.{}, &waiters.fo))
            continue;
        if (EnumCheckOnce(arg, &.{"-co"}, IOKind, .Console, &o_kind))
            continue;

        if (BoolCheck(arg, &.{ "-tty", "--allow-tty" }, &b_allow_tty))
            continue;

        if (BoolCheck(arg, &.{ "-h", "--help" }, &b_show_help))
            break;

        const ts = RawCheck(arg, &.{ "-ts", "--tab-size" });
        if (StageTwoCheck(alloc, arg, ts, usize, &fmt.TabSize, def_fmt.TabSize, &waiters.ts))
            continue;
        const mbl = RawCheck(arg, &.{ "-mbl", "--max-blank-lines" });
        if (StageTwoCheck(alloc, arg, mbl, usize, &fmt.MaxBlankLines, def_fmt.MaxBlankLines, &waiters.mbl))
            continue;
        const tcc = RawCheck(arg, &.{ "-tcc", "--text-comment-column" });
        if (StageTwoCheck(alloc, arg, tcc, usize, &fmt.TextComCol, def_fmt.TextComCol, &waiters.tcc))
            continue;
        const tia = RawCheck(arg, &.{ "-tia", "--text-instruction-advance" });
        if (StageTwoCheck(alloc, arg, tia, usize, &fmt.TextInsMinAdv, def_fmt.TextInsMinAdv, &waiters.tia))
            continue;
        const toa = RawCheck(arg, &.{ "-toa", "--text-operands-advance" });
        if (StageTwoCheck(alloc, arg, toa, usize, &fmt.TextOpsMinAdv, def_fmt.TextOpsMinAdv, &waiters.toa))
            continue;
        const dcc = RawCheck(arg, &.{ "-dcc", "--data-comment-column" });
        if (StageTwoCheck(alloc, arg, dcc, usize, &fmt.DataComCol, def_fmt.DataComCol, &waiters.dcc))
            continue;
        const dia = RawCheck(arg, &.{ "-dia", "--data-instruction-advance" });
        if (StageTwoCheck(alloc, arg, dia, usize, &fmt.DataInsMinAdv, def_fmt.DataInsMinAdv, &waiters.dia))
            continue;
        const doa = RawCheck(arg, &.{ "-doa", "--data-operands-advance" });
        if (StageTwoCheck(alloc, arg, doa, usize, &fmt.DataOpsMinAdv, def_fmt.DataOpsMinAdv, &waiters.doa))
            continue;
        const sin = RawCheck(arg, &.{ "-sin", "--section-indent-none" });
        if (StageTwoCheck(alloc, arg, sin, usize, &fmt.SecIndentNone, def_fmt.SecIndentNone, &waiters.sin))
            continue;
        const sid = RawCheck(arg, &.{ "-sid", "--section-indent-data" });
        if (StageTwoCheck(alloc, arg, sid, usize, &fmt.SecIndentData, def_fmt.SecIndentData, &waiters.sid))
            continue;
        const sit = RawCheck(arg, &.{ "-sit", "--section-indent-text" });
        if (StageTwoCheck(alloc, arg, sit, usize, &fmt.SecIndentText, def_fmt.SecIndentText, &waiters.sit))
            continue;
        const sio = RawCheck(arg, &.{ "-sio", "--section-indent-other" });
        if (StageTwoCheck(alloc, arg, sio, usize, &fmt.SecIndentOther, def_fmt.SecIndentOther, &waiters.sio))
            continue;

        if (arg[0] == '-')
            return Error.UnknownFlag;

        if (i_kind != null) break;
        i_kind = .File;
        i_file = try alloc.dupe(u8, arg);
    }

    if (waiters.AnyWaiting()) return Error.MissingArgumentValue;

    if (i_kind == null) i_kind = .Console;
    if (o_kind == null) o_kind = i_kind;
    if (o_kind == .File and (o_file.len == 0 or eql(u8, i_file, o_file))) {
        alloc.free(o_file);
        o_file = try std.fmt.allocPrint(alloc, "{s}.tmp", .{i_file});
        b_io_file_same = true;
    }

    assert(i_kind != .File or i_file.len > 0);
    assert(o_kind != .File or o_file.len > 0);
    return AppSettings{
        .Format = fmt,
        .bAllowTty = b_allow_tty,
        .bShowHelp = b_show_help,
        .bIOFileSame = b_io_file_same,
        .IKind = i_kind.?,
        .OKind = o_kind.?,
        .IFile = i_file,
        .OFile = o_file,
    };
}

/// should be called with the original allocator if either IKind or OKind are File
pub fn Deinit(self: *AppSettings, alloc: Allocator) void {
    alloc.free(self.IFile);
    alloc.free(self.OFile);
}

test "Settings" {
    const AppSettingsTestCase = struct {
        in: []const [:0]const u8,
        ex: AppSettings = .default,
        err: ?Error = null,
    };

    // TODO: handle case where i/o type is double-specified, but the type is not
    //  the same, like below
    //      "-co -fo filename"  <- specifying file output when console out already set
    // TODO: ?? double-specifying input/output files specifically should return
    //  error instead of ignore? as a way of communicating correct usage to user
    // TODO: ?? maybe don't return an error in cases like below (double-specified
    //  two-part args when second left hanging), as the value is actually set prior
    //      "-ts 99 -ts" -> Error.MissingArgumentValue
    // TODO: ?? tests for option order (free-ness); not decided on the degree to
    //  which the order is "free", esp. wrt in-out opts
    const test_cases = [_]AppSettingsTestCase{
        .{
            // default settings (stdin -> stdout)
            .in = &.{},
        },
        .{
            // file -> replace file
            .in = &.{"filename"},
            .ex = blk: {
                var ex: AppSettings = .default;
                ex.IFile = "filename";
                ex.IKind = .File;
                ex.OFile = "filename.tmp";
                ex.OKind = .File;
                ex.bIOFileSame = true;
                break :blk ex;
            },
        },
        .{
            // file -> replace file (two commands)
            .in = &.{ "filename", "-fo", "filename" },
            .ex = blk: {
                var ex: AppSettings = .default;
                ex.IFile = "filename";
                ex.IKind = .File;
                ex.OFile = "filename.tmp";
                ex.OKind = .File;
                ex.bIOFileSame = true;
                break :blk ex;
            },
        },
        .{
            // file -> new file
            .in = &.{ "filename1", "-fo", "filename2" },
            .ex = blk: {
                var ex: AppSettings = .default;
                ex.IFile = "filename1";
                ex.IKind = .File;
                ex.OFile = "filename2";
                ex.OKind = .File;
                break :blk ex;
            },
        },
        .{
            // stdin -> file
            .in = &.{ "-fo", "filename" },
            .ex = blk: {
                var ex: AppSettings = .default;
                ex.OFile = "filename";
                ex.OKind = .File;
                break :blk ex;
            },
        },
        .{
            // file -> stdout
            .in = &.{ "filename", "-co" },
            .ex = blk: {
                var ex: AppSettings = .default;
                ex.IFile = "filename";
                ex.IKind = .File;
                break :blk ex;
            },
        },
        .{
            // help shorthand
            .in = &.{"-h"},
            .ex = blk: {
                var ex: AppSettings = .default;
                ex.bShowHelp = true;
                break :blk ex;
            },
        },
        .{
            // help long form
            .in = &.{"--help"},
            .ex = blk: {
                var ex: AppSettings = .default;
                ex.bShowHelp = true;
                break :blk ex;
            },
        },
        .{
            // tty shorthand
            .in = &.{"-tty"},
            .ex = blk: {
                var ex: AppSettings = .default;
                ex.bAllowTty = true;
                break :blk ex;
            },
        },
        .{
            // tty long form
            .in = &.{"--allow-tty"},
            .ex = blk: {
                var ex: AppSettings = .default;
                ex.bAllowTty = true;
                break :blk ex;
            },
        },
        .{
            // cosmetic shorthand
            .in = &.{
                "-ts",  "101", "-mbl", "102", "-tcc", "103",
                "-tia", "104", "-toa", "105", "-dcc", "106",
                "-dia", "107", "-doa", "108", "-sin", "109",
                "-sid", "110", "-sit", "111", "-sio", "112",
            },
            .ex = blk: {
                var ex: AppSettings = .default;
                ex.Format.TabSize = 101;
                ex.Format.MaxBlankLines = 102;
                ex.Format.TextComCol = 103;
                ex.Format.TextInsMinAdv = 104;
                ex.Format.TextOpsMinAdv = 105;
                ex.Format.DataComCol = 106;
                ex.Format.DataInsMinAdv = 107;
                ex.Format.DataOpsMinAdv = 108;
                ex.Format.SecIndentNone = 109;
                ex.Format.SecIndentData = 110;
                ex.Format.SecIndentText = 111;
                ex.Format.SecIndentOther = 112;
                break :blk ex;
            },
        },
        .{
            // cosmetic long form
            .in = &.{
                "--tab-size",                 "101", "--max-blank-lines",          "102",
                "--text-comment-column",      "103", "--text-instruction-advance", "104",
                "--text-operands-advance",    "105", "--data-comment-column",      "106",
                "--data-instruction-advance", "107", "--data-operands-advance",    "108",
                "--section-indent-none",      "109", "--section-indent-data",      "110",
                "--section-indent-text",      "111", "--section-indent-other",     "112",
            },
            .ex = blk: {
                var ex: AppSettings = .default;
                ex.Format.TabSize = 101;
                ex.Format.MaxBlankLines = 102;
                ex.Format.TextComCol = 103;
                ex.Format.TextInsMinAdv = 104;
                ex.Format.TextOpsMinAdv = 105;
                ex.Format.DataComCol = 106;
                ex.Format.DataInsMinAdv = 107;
                ex.Format.DataOpsMinAdv = 108;
                ex.Format.SecIndentNone = 109;
                ex.Format.SecIndentData = 110;
                ex.Format.SecIndentText = 111;
                ex.Format.SecIndentOther = 112;
                break :blk ex;
            },
        },
        .{
            // cosmetic apply once
            .in = &.{
                "-ts",  "101", "-mbl", "102", "-tcc", "103",
                "-tia", "104", "-toa", "105", "-dcc", "106",
                "-dia", "107", "-doa", "108", "-sin", "109",
                "-sid", "110", "-sit", "111", "-sio", "112",
                "-ts",  "113", "-mbl", "114", "-tcc", "115",
                "-tia", "116", "-toa", "117", "-dcc", "118",
                "-dia", "119", "-doa", "120", "-sin", "121",
                "-sid", "122", "-sit", "123", "-sio", "124",
            },
            .ex = blk: {
                var ex: AppSettings = .default;
                ex.Format.TabSize = 101;
                ex.Format.MaxBlankLines = 102;
                ex.Format.TextComCol = 103;
                ex.Format.TextInsMinAdv = 104;
                ex.Format.TextOpsMinAdv = 105;
                ex.Format.DataComCol = 106;
                ex.Format.DataInsMinAdv = 107;
                ex.Format.DataOpsMinAdv = 108;
                ex.Format.SecIndentNone = 109;
                ex.Format.SecIndentData = 110;
                ex.Format.SecIndentText = 111;
                ex.Format.SecIndentOther = 112;
                break :blk ex;
            },
        },
        .{
            // file output apply once
            .in = &.{ "-fo", "filename1", "-fo", "filename2" },
            .ex = blk: {
                var ex: AppSettings = .default;
                ex.OFile = "filename1";
                ex.OKind = .File;
                break :blk ex;
            },
        },
        .{
            // TODO: maybe this case should simply ignore the missing value since
            //  the value is already set?
            .in = &.{ "filename1", "filename2" },
            .ex = blk: {
                var ex: AppSettings = .default;
                ex.IFile = "filename1";
                ex.IKind = .File;
                ex.OFile = "filename1.tmp";
                ex.OKind = .File;
                ex.bIOFileSame = true;
                break :blk ex;
            },
        },
        // error: two-part options left hanging
        .{ .in = &.{"-fo"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"-ts"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"-mbl"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"-tcc"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"-tia"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"-toa"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"-dcc"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"-dia"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"-doa"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"-sin"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"-sid"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"-sit"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"-sio"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"--tab-size"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"--max-blank-lines"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"--text-comment-column"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"--text-instruction-advance"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"--text-operands-advance"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"--data-comment-column"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"--data-instruction-advance"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"--data-operands-advance"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"--section-indent-none"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"--section-indent-data"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"--section-indent-text"}, .err = Error.MissingArgumentValue },
        .{ .in = &.{"--section-indent-other"}, .err = Error.MissingArgumentValue },
        // TODO: maybe these cases should simply ignore the missing value since
        //  the value is already set?
        // error: double-specified two-part option left hanging on second spec
        .{ .in = &.{ "-fo", "filename1", "-fo" }, .err = Error.MissingArgumentValue },
        .{ .in = &.{ "-ts", "9999", "-ts" }, .err = Error.MissingArgumentValue },
        .{ .in = &.{ "-mbl", "9999", "-mbl" }, .err = Error.MissingArgumentValue },
        .{ .in = &.{ "-tcc", "9999", "-tcc" }, .err = Error.MissingArgumentValue },
        .{ .in = &.{ "-tia", "9999", "-tia" }, .err = Error.MissingArgumentValue },
        .{ .in = &.{ "-toa", "9999", "-toa" }, .err = Error.MissingArgumentValue },
        .{ .in = &.{ "-dcc", "9999", "-dcc" }, .err = Error.MissingArgumentValue },
        .{ .in = &.{ "-dia", "9999", "-dia" }, .err = Error.MissingArgumentValue },
        .{ .in = &.{ "-doa", "9999", "-doa" }, .err = Error.MissingArgumentValue },
        .{ .in = &.{ "-sin", "9999", "-sin" }, .err = Error.MissingArgumentValue },
        .{ .in = &.{ "-sid", "9999", "-sid" }, .err = Error.MissingArgumentValue },
        .{ .in = &.{ "-sit", "9999", "-sit" }, .err = Error.MissingArgumentValue },
        .{ .in = &.{ "-sio", "9999", "-sio" }, .err = Error.MissingArgumentValue },
        .{
            .in = &.{ "--tab-size", "9999", "--tab-size" },
            .err = Error.MissingArgumentValue,
        },
        .{
            .in = &.{ "--max-blank-lines", "9999", "--max-blank-lines" },
            .err = Error.MissingArgumentValue,
        },
        .{
            .in = &.{ "--text-comment-column", "9999", "--text-comment-column" },
            .err = Error.MissingArgumentValue,
        },
        .{
            .in = &.{ "--text-instruction-advance", "9999", "--text-instruction-advance" },
            .err = Error.MissingArgumentValue,
        },
        .{
            .in = &.{ "--text-operands-advance", "9999", "--text-operands-advance" },
            .err = Error.MissingArgumentValue,
        },
        .{
            .in = &.{ "--data-comment-column", "9999", "--data-comment-column" },
            .err = Error.MissingArgumentValue,
        },
        .{
            .in = &.{ "--data-instruction-advance", "9999", "--data-instruction-advance" },
            .err = Error.MissingArgumentValue,
        },
        .{
            .in = &.{ "--data-operands-advance", "9999", "--data-operands-advance" },
            .err = Error.MissingArgumentValue,
        },
        .{
            .in = &.{ "--section-indent-none", "9999", "--section-indent-none" },
            .err = Error.MissingArgumentValue,
        },
        .{
            .in = &.{ "--section-indent-data", "9999", "--section-indent-data" },
            .err = Error.MissingArgumentValue,
        },
        .{
            .in = &.{ "--section-indent-text", "9999", "--section-indent-text" },
            .err = Error.MissingArgumentValue,
        },
        .{
            .in = &.{ "--section-indent-other", "9999", "--section-indent-other" },
            .err = Error.MissingArgumentValue,
        },
        // error: invalid/unknown flag
        .{ .in = &.{"--will-never-be-a-real-flag-surely"}, .err = Error.UnknownFlag },
    };

    std.testing.log_level = .debug;
    for (test_cases, 0..) |t, i| {
        //errdefer std.debug.print("FAILED {d:0>2} :: {any}\n\n", .{ i, t.in });
        errdefer std.debug.print("FAILED {d:0>2}\n\n", .{i});
        const alloc = std.testing.allocator;

        const result = ParseCLI(alloc, t.in);

        if (t.err) |t_err| {
            try std.testing.expectError(t_err, result);
        } else {
            var r = try result;
            try std.testing.expectEqualDeep(t.ex, r);
            r.Deinit(alloc);
        }
    }
}
