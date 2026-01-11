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
const asBytes = std.mem.asBytes;

const CLI = @import("utl_cli.zig");

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

Format: FormatSettings,
IKind: IOKind,
OKind: IOKind,
IFile: []const u8,
OFile: []const u8,
bAllowTty: bool,
bShowHelp: bool,
/// Implies that IKind and OKind are both File. If true, OFile will match IFile
/// but with ".tmp" appended; after formatting, the caller can simply delete
/// IFile and rename OFile in response to this being true.
bIOFileSame: bool,

pub const default: AppSettings = .{
    .Format = .default,
    .bAllowTty = false,
    .bShowHelp = false,
    .bIOFileSame = false,
    .IKind = .Console,
    .OKind = .Console,
    .IFile = &.{},
    .OFile = &.{},
};

// TODO: maybe just take the whole cli, including exe name, to simplify things
//  so that you don't have to know that you need to skip
/// Populate settings by parsing command line arguments. Assumes that `args` will
/// be allocated for the lifetime of the program (until the filenames are no longer
/// needed).
pub fn ParseArguments(self: *AppSettings, args: []const [:0]const u8) CLI.Error!void {
    assert(eql(u8, asBytes(self), asBytes(&AppSettings.default)));
    defer assert(self.IKind != .File or self.IFile.len > 0);
    defer assert(self.OKind != .File or self.OFile.len > 0);

    var okind_intermediate: ?IOKind = null;
    const IOKindFlagT = CLI.FlagContext(?IOKind, void);
    const IOKindStringFlagT = CLI.FlagContext(?IOKind, []const u8);
    var okind_flag_co: IOKindFlagT = .createArg(&okind_intermediate, .Console, "-co", &.{});
    var okind_flag_fo: IOKindStringFlagT = .create(&okind_intermediate, .File, &self.OFile, "-fo", &.{});

    const BoolFlagT = CLI.FlagContext(bool, void);
    var ctx_bool = [_]BoolFlagT{
        .createArg(&self.bAllowTty, true, "-tty", "--allow-tty"),
        .createArg(&self.bShowHelp, true, "-h", "--help"),
    };

    const U32OptT = CLI.FlagContext(void, u32);
    var ctx_value_u32 = [_]U32OptT{
        .createOpt(&self.Format.TabSize, "-ts", "--tab-size"),
        .createOpt(&self.Format.MaxBlankLines, "-mbl", "--max-blank-lines"),
        .createOpt(&self.Format.TextComCol, "-tcc", "--text-comment-column"),
        .createOpt(&self.Format.TextInsMinAdv, "-tia", "--text-instruction-advance"),
        .createOpt(&self.Format.TextOpsMinAdv, "-toa", "--text-operands-advance"),
        .createOpt(&self.Format.DataComCol, "-dcc", "--data-comment-column"),
        .createOpt(&self.Format.DataInsMinAdv, "-dia", "--data-instruction-advance"),
        .createOpt(&self.Format.DataOpsMinAdv, "-doa", "--data-operands-advance"),
        .createOpt(&self.Format.SecIndentNone, "-sin", "--section-indent-none"),
        .createOpt(&self.Format.SecIndentData, "-sid", "--section-indent-data"),
        .createOpt(&self.Format.SecIndentText, "-sit", "--section-indent-text"),
        .createOpt(&self.Format.SecIndentOther, "-sio", "--section-indent-other"),
    };

    // TODO: standardized way (i.e. part of the cli module) to "push" options to the cli
    const cli = CLI{
        .options = &opts: {
            const OPTS_LEN: usize = 2 + ctx_bool.len + ctx_value_u32.len;
            var opts: [OPTS_LEN]CLI.Option = undefined;
            var START: usize = 0;
            defer assert(START == OPTS_LEN);

            opts[0] = okind_flag_co.option();
            opts[1] = okind_flag_fo.option();
            START += 2;

            for (&ctx_bool, START..) |*ctx, i| opts[i] = ctx.option();
            START += ctx_bool.len;

            for (&ctx_value_u32, START..) |*ctx, i| opts[i] = ctx.option();
            START += ctx_value_u32.len;

            break :opts opts;
        },
    };

    // TODO: standardized way (i.e. part of the cli module) to process cli flags
    var arg_i: usize = 0;
    while (arg_i < args.len) : (arg_i += 1) {
        const arg = args[arg_i];
        const args_remaining = args[arg_i..];

        if (opt: {
            for (cli.options) |opt| {
                const n = try opt.Check(args_remaining);
                if (n > 0) {
                    arg_i += n - 1;
                    break :opt true;
                }
            }
            break :opt false;
        }) continue;

        if (arg[0] == '-')
            return error.UnknownFlag;

        if (self.IFile.len > 0) break;
        self.IFile = arg;
    }

    if (self.IFile.len > 0)
        self.IKind = .File;

    self.OKind = if (okind_intermediate) |k| k else self.IKind;
    if (self.OKind == .File and self.OFile.len == 0) {
        self.OFile = self.IFile;
    }
}

// NOTE: logic pulled out from `ParseArguments` in order to prevent polluting it
// with an allocator api, and allowing some variation in the timing of the resolution
// (and thus memory commitment) of the output filename.
/// Finalizes the output filename. When the output file is the input file, a temp
/// filename will be allocated, replacing `OFile`. Call `Deinit` to cleanup.
pub fn ResolveOutputFilename(self: *AppSettings, alloc: Allocator) !void {
    if (self.OKind == .File and (self.OFile.len == 0 or eql(u8, self.IFile, self.OFile))) {
        self.OFile = try std.fmt.allocPrint(alloc, "{s}.tmp", .{self.IFile});
        self.bIOFileSame = true;
    }
}

/// Must be called if calling `ResolveOutputFilename`.
pub fn Deinit(self: *const AppSettings, alloc: Allocator) void {
    if (self.bIOFileSame)
        alloc.free(self.OFile);
}

test "Settings" {
    const AppSettingsTestCase = struct {
        in: []const [:0]const u8,
        ex: AppSettings = .default,
        err: ?CLI.Error = null,
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
        .{ .in = &.{"-fo"}, .err = error.MissingFlagOption },
        .{ .in = &.{"-ts"}, .err = error.MissingFlagOption },
        .{ .in = &.{"-mbl"}, .err = error.MissingFlagOption },
        .{ .in = &.{"-tcc"}, .err = error.MissingFlagOption },
        .{ .in = &.{"-tia"}, .err = error.MissingFlagOption },
        .{ .in = &.{"-toa"}, .err = error.MissingFlagOption },
        .{ .in = &.{"-dcc"}, .err = error.MissingFlagOption },
        .{ .in = &.{"-dia"}, .err = error.MissingFlagOption },
        .{ .in = &.{"-doa"}, .err = error.MissingFlagOption },
        .{ .in = &.{"-sin"}, .err = error.MissingFlagOption },
        .{ .in = &.{"-sid"}, .err = error.MissingFlagOption },
        .{ .in = &.{"-sit"}, .err = error.MissingFlagOption },
        .{ .in = &.{"-sio"}, .err = error.MissingFlagOption },
        .{ .in = &.{"--tab-size"}, .err = error.MissingFlagOption },
        .{ .in = &.{"--max-blank-lines"}, .err = error.MissingFlagOption },
        .{ .in = &.{"--text-comment-column"}, .err = error.MissingFlagOption },
        .{ .in = &.{"--text-instruction-advance"}, .err = error.MissingFlagOption },
        .{ .in = &.{"--text-operands-advance"}, .err = error.MissingFlagOption },
        .{ .in = &.{"--data-comment-column"}, .err = error.MissingFlagOption },
        .{ .in = &.{"--data-instruction-advance"}, .err = error.MissingFlagOption },
        .{ .in = &.{"--data-operands-advance"}, .err = error.MissingFlagOption },
        .{ .in = &.{"--section-indent-none"}, .err = error.MissingFlagOption },
        .{ .in = &.{"--section-indent-data"}, .err = error.MissingFlagOption },
        .{ .in = &.{"--section-indent-text"}, .err = error.MissingFlagOption },
        .{ .in = &.{"--section-indent-other"}, .err = error.MissingFlagOption },
        // TODO: maybe these cases should simply ignore the missing value since
        //  the value is already set?
        // error: double-specified two-part option left hanging on second spec
        .{ .in = &.{ "-fo", "filename1", "-fo" }, .err = error.MissingFlagOption },
        .{ .in = &.{ "-ts", "9999", "-ts" }, .err = error.MissingFlagOption },
        .{ .in = &.{ "-mbl", "9999", "-mbl" }, .err = error.MissingFlagOption },
        .{ .in = &.{ "-tcc", "9999", "-tcc" }, .err = error.MissingFlagOption },
        .{ .in = &.{ "-tia", "9999", "-tia" }, .err = error.MissingFlagOption },
        .{ .in = &.{ "-toa", "9999", "-toa" }, .err = error.MissingFlagOption },
        .{ .in = &.{ "-dcc", "9999", "-dcc" }, .err = error.MissingFlagOption },
        .{ .in = &.{ "-dia", "9999", "-dia" }, .err = error.MissingFlagOption },
        .{ .in = &.{ "-doa", "9999", "-doa" }, .err = error.MissingFlagOption },
        .{ .in = &.{ "-sin", "9999", "-sin" }, .err = error.MissingFlagOption },
        .{ .in = &.{ "-sid", "9999", "-sid" }, .err = error.MissingFlagOption },
        .{ .in = &.{ "-sit", "9999", "-sit" }, .err = error.MissingFlagOption },
        .{ .in = &.{ "-sio", "9999", "-sio" }, .err = error.MissingFlagOption },
        .{
            .in = &.{ "--tab-size", "9999", "--tab-size" },
            .err = error.MissingFlagOption,
        },
        .{
            .in = &.{ "--max-blank-lines", "9999", "--max-blank-lines" },
            .err = error.MissingFlagOption,
        },
        .{
            .in = &.{ "--text-comment-column", "9999", "--text-comment-column" },
            .err = error.MissingFlagOption,
        },
        .{
            .in = &.{ "--text-instruction-advance", "9999", "--text-instruction-advance" },
            .err = error.MissingFlagOption,
        },
        .{
            .in = &.{ "--text-operands-advance", "9999", "--text-operands-advance" },
            .err = error.MissingFlagOption,
        },
        .{
            .in = &.{ "--data-comment-column", "9999", "--data-comment-column" },
            .err = error.MissingFlagOption,
        },
        .{
            .in = &.{ "--data-instruction-advance", "9999", "--data-instruction-advance" },
            .err = error.MissingFlagOption,
        },
        .{
            .in = &.{ "--data-operands-advance", "9999", "--data-operands-advance" },
            .err = error.MissingFlagOption,
        },
        .{
            .in = &.{ "--section-indent-none", "9999", "--section-indent-none" },
            .err = error.MissingFlagOption,
        },
        .{
            .in = &.{ "--section-indent-data", "9999", "--section-indent-data" },
            .err = error.MissingFlagOption,
        },
        .{
            .in = &.{ "--section-indent-text", "9999", "--section-indent-text" },
            .err = error.MissingFlagOption,
        },
        .{
            .in = &.{ "--section-indent-other", "9999", "--section-indent-other" },
            .err = error.MissingFlagOption,
        },
        // error: invalid/unknown flag
        .{ .in = &.{"--will-never-be-a-real-flag-surely"}, .err = error.UnknownFlag },
    };

    std.testing.log_level = .debug;
    for (test_cases, 0..) |t, i| {
        //errdefer std.debug.print("FAILED {d:0>2} :: {any}\n\n", .{ i, t.in });
        errdefer std.debug.print("FAILED {d:0>2}\n\n", .{i});
        const alloc = std.testing.allocator;

        var settings: AppSettings = .default;
        const result = settings.ParseArguments(t.in);

        if (t.err) |t_err| {
            try std.testing.expectError(t_err, result);
        } else {
            try settings.ResolveOutputFilename(alloc);
            defer settings.Deinit(alloc);
            try std.testing.expectEqualDeep(t.ex, settings);
        }
    }
}
