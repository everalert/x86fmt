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
// TODO: ?? verify any asm input files here instead of punting

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

pub const IOKind = enum { Console, File };

pub const Error = CLI.Error;

// TODO: ?? rename to `fromArguments` change usage to be like a decl literal?
// TODO: maybe just take the whole cli, including exe name, to simplify things
//  so that you don't have to know that you need to skip
/// Populate settings by parsing command line arguments. Assumes that `args` will
/// be allocated for the lifetime of the program (until the filenames are no longer
/// needed).
pub fn ParseArguments(self: *AppSettings, alloc: Allocator, args: []const [:0]const u8) Error!void {
    assert(eql(u8, asBytes(self), asBytes(&AppSettings.default)));
    defer assert(self.IKind != .File or self.IFile.len > 0);
    defer assert(self.OKind != .File or self.OFile.len > 0);

    var arena: std.heap.ArenaAllocator = .init(alloc);
    defer _ = arena.reset(.free_all);
    const arena_alloc = arena.allocator();

    var amt_flags: usize = 0;

    const StrUserValueT = CLI.UserValueContext([]const u8);
    var ifile_user_value: StrUserValueT = .create(&self.IFile);

    var okind_intermediate: ?IOKind = null;
    const IOKindFlagT = CLI.FlagContext(?IOKind, void);
    const IOKindStringFlagT = CLI.FlagContext(?IOKind, []const u8);
    var okind_flag_co: IOKindFlagT = .createArg(&okind_intermediate, .Console, "-co", &.{});
    var okind_flag_fo: IOKindStringFlagT = .create(&okind_intermediate, .File, &self.OFile, "-fo", &.{});
    amt_flags += 2;

    const BoolFlagT = CLI.FlagContext(bool, void);
    var ctx_bool = [_]BoolFlagT{
        .createArg(&self.bAllowTty, true, "-tty", "--allow-tty"),
        .createArg(&self.bShowHelp, true, "-h", "--help"),
    };
    amt_flags += ctx_bool.len;

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
    amt_flags += ctx_value_u32.len;

    var cli: CLI = try .initCapacity(arena_alloc, amt_flags);
    try cli.AppendOption(arena_alloc, IOKindFlagT, &okind_flag_co);
    try cli.AppendOption(arena_alloc, IOKindStringFlagT, &okind_flag_fo);
    try cli.AppendOptions(arena_alloc, BoolFlagT, &ctx_bool);
    try cli.AppendOptions(arena_alloc, U32OptT, &ctx_value_u32);
    cli.default_option = &ifile_user_value.option();

    try cli.ParseArguments(args);

    if (self.IFile.len > 0)
        self.IKind = .File;

    self.OKind = okind_intermediate orelse self.IKind;
    if (self.OKind == .File and self.OFile.len == 0)
        self.OFile = self.IFile;
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

test "Settings" {
    const AppSettingsTestCase = struct {
        in: []const [:0]const u8,
        ex: AppSettings = .default,
        err: ?Error = null,
    };

    // TODO: review these tests and cut down any that seem needless now that the
    //  cli system itself is testing systemic behaviour; punting for now since
    //  it's strictly not necessary to cut any.
    // TODO: tests for when flags indirectly repeated using long and short form
    //      .{ "-ts", "8", "--tab-size", "12" } // error
    // TODO: tests for flags repeating? currently, flags can technically repeat
    //  if they aren't associated with a value or the value they set is the same
    //  as the default, so you could actually physically repeat them, even though
    //  it would have no effect in current impl. however, this is only not an
    //  issue because of the current usage's (lack of) coverage
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
            .err = error.OptionRepeated,
        },
        // output set once
        .{ .in = &.{ "-co", "-fo", "filename" }, .err = error.FlagRepeated },
        .{ .in = &.{ "-fo", "filename", "-co" }, .err = error.FlagRepeated },
        .{ .in = &.{ "filename1", "filename2" }, .err = error.OptionRepeated },
        // file output apply once
        .{ .in = &.{ "-fo", "filename1", "-fo", "filename2" }, .err = error.FlagRepeated },
        // error: two-part options left hanging
        .{ .in = &.{"-fo"}, .err = error.FlagMissingOption },
        .{ .in = &.{"-ts"}, .err = error.FlagMissingOption },
        .{ .in = &.{"-mbl"}, .err = error.FlagMissingOption },
        .{ .in = &.{"-tcc"}, .err = error.FlagMissingOption },
        .{ .in = &.{"-tia"}, .err = error.FlagMissingOption },
        .{ .in = &.{"-toa"}, .err = error.FlagMissingOption },
        .{ .in = &.{"-dcc"}, .err = error.FlagMissingOption },
        .{ .in = &.{"-dia"}, .err = error.FlagMissingOption },
        .{ .in = &.{"-doa"}, .err = error.FlagMissingOption },
        .{ .in = &.{"-sin"}, .err = error.FlagMissingOption },
        .{ .in = &.{"-sid"}, .err = error.FlagMissingOption },
        .{ .in = &.{"-sit"}, .err = error.FlagMissingOption },
        .{ .in = &.{"-sio"}, .err = error.FlagMissingOption },
        .{ .in = &.{"--tab-size"}, .err = error.FlagMissingOption },
        .{ .in = &.{"--max-blank-lines"}, .err = error.FlagMissingOption },
        .{ .in = &.{"--text-comment-column"}, .err = error.FlagMissingOption },
        .{ .in = &.{"--text-instruction-advance"}, .err = error.FlagMissingOption },
        .{ .in = &.{"--text-operands-advance"}, .err = error.FlagMissingOption },
        .{ .in = &.{"--data-comment-column"}, .err = error.FlagMissingOption },
        .{ .in = &.{"--data-instruction-advance"}, .err = error.FlagMissingOption },
        .{ .in = &.{"--data-operands-advance"}, .err = error.FlagMissingOption },
        .{ .in = &.{"--section-indent-none"}, .err = error.FlagMissingOption },
        .{ .in = &.{"--section-indent-data"}, .err = error.FlagMissingOption },
        .{ .in = &.{"--section-indent-text"}, .err = error.FlagMissingOption },
        .{ .in = &.{"--section-indent-other"}, .err = error.FlagMissingOption },
        // error: double-specified two-part option left hanging on second spec
        .{ .in = &.{ "-fo", "filename1", "-fo" }, .err = error.FlagRepeated },
        // the following expects FlagMissingOption because there is no arg value
        .{ .in = &.{ "-ts", "9999", "-ts" }, .err = error.OptionRepeated },
        .{ .in = &.{ "-mbl", "9999", "-mbl" }, .err = error.OptionRepeated },
        .{ .in = &.{ "-tcc", "9999", "-tcc" }, .err = error.OptionRepeated },
        .{ .in = &.{ "-tia", "9999", "-tia" }, .err = error.OptionRepeated },
        .{ .in = &.{ "-toa", "9999", "-toa" }, .err = error.OptionRepeated },
        .{ .in = &.{ "-dcc", "9999", "-dcc" }, .err = error.OptionRepeated },
        .{ .in = &.{ "-dia", "9999", "-dia" }, .err = error.OptionRepeated },
        .{ .in = &.{ "-doa", "9999", "-doa" }, .err = error.OptionRepeated },
        .{ .in = &.{ "-sin", "9999", "-sin" }, .err = error.OptionRepeated },
        .{ .in = &.{ "-sid", "9999", "-sid" }, .err = error.OptionRepeated },
        .{ .in = &.{ "-sit", "9999", "-sit" }, .err = error.OptionRepeated },
        .{ .in = &.{ "-sio", "9999", "-sio" }, .err = error.OptionRepeated },
        .{
            .in = &.{ "--tab-size", "9999", "--tab-size" },
            .err = error.OptionRepeated,
        },
        .{
            .in = &.{ "--max-blank-lines", "9999", "--max-blank-lines" },
            .err = error.OptionRepeated,
        },
        .{
            .in = &.{ "--text-comment-column", "9999", "--text-comment-column" },
            .err = error.OptionRepeated,
        },
        .{
            .in = &.{ "--text-instruction-advance", "9999", "--text-instruction-advance" },
            .err = error.OptionRepeated,
        },
        .{
            .in = &.{ "--text-operands-advance", "9999", "--text-operands-advance" },
            .err = error.OptionRepeated,
        },
        .{
            .in = &.{ "--data-comment-column", "9999", "--data-comment-column" },
            .err = error.OptionRepeated,
        },
        .{
            .in = &.{ "--data-instruction-advance", "9999", "--data-instruction-advance" },
            .err = error.OptionRepeated,
        },
        .{
            .in = &.{ "--data-operands-advance", "9999", "--data-operands-advance" },
            .err = error.OptionRepeated,
        },
        .{
            .in = &.{ "--section-indent-none", "9999", "--section-indent-none" },
            .err = error.OptionRepeated,
        },
        .{
            .in = &.{ "--section-indent-data", "9999", "--section-indent-data" },
            .err = error.OptionRepeated,
        },
        .{
            .in = &.{ "--section-indent-text", "9999", "--section-indent-text" },
            .err = error.OptionRepeated,
        },
        .{
            .in = &.{ "--section-indent-other", "9999", "--section-indent-other" },
            .err = error.OptionRepeated,
        },
        // error: invalid/unknown flag
        .{ .in = &.{"--will-never-be-a-real-flag-surely"}, .err = error.FlagUnknown },
        // invalid option: u32
        .{ .in = &.{ "--section-indent-other", "many-cols-plis" }, .err = error.OptionInvalid },
    };

    std.testing.log_level = .debug;
    for (test_cases, 0..) |t, i| {
        //errdefer std.debug.print("FAILED {d:0>2} :: {any}\n\n", .{ i, t.in });
        errdefer std.debug.print("FAILED {d:0>2}\n\n", .{i});
        const alloc = std.testing.allocator;

        var settings: AppSettings = .default;
        const result = settings.ParseArguments(alloc, t.in);
        try settings.ResolveOutputFilename(alloc);
        defer settings.Deinit(alloc);

        try std.testing.expectEqual(t.err orelse {}, result);
        if (t.err == null) try std.testing.expectEqualDeep(t.ex, settings);
    }
}
