//! Reads settings from the command line. Arguments can be provided in any order
//! and will short-circuit if repeated. See HelpText for details on options and
//! usage.
//!
//! Settings provided by this module:
//! - Input mode; defaults to stdin
//! - Output mode; defaults to matching the input setting
//! - Input file; set input to File mode by providing a file path
//! - Output file; will overwrite input file, unless output file specified
//! - Show Help flag
//! - Configuration of formatting values (comment column, etc.)
const CLI = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const eql = std.mem.eql;

const FormatSettings = @import("format.zig").Settings;
const VERSION_STRING = @import("version.zig").VERSION_STRING;

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
    \\  -dcc [num], --data-comment-column [num]         default 64
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
pub const CLIError = error{InvalidTwoPartArgument};

FmtSettings: FormatSettings,
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

// TODO: verify any files here instead of punting?
// TODO: add tests. may need to rework input mechanism for testability, since
//  Parse reads the process arguments directly.

const Waiters = struct {
    fo: bool = false,
    ts: bool = false,
    mbl: bool = false,
    tcc: bool = false,
    tia: bool = false,
    toa: bool = false,
    dcc: bool = false,
    dia: bool = false,
    doa: bool = false,
    sin: bool = false,
    sid: bool = false,
    sit: bool = false,
    sio: bool = false,

    pub fn AnyWaiting(self: *const Waiters) bool {
        var cnt_true: usize = 0;
        inline for (std.meta.fields(Waiters)) |f| {
            comptime assert(f.type == bool);
            cnt_true += @intFromBool(@field(self, f.name));
        }
        return cnt_true > 0;
    }
};

/// Parse command line arguments and generate a CLI settings object. Caller is
/// responsible for freeing memory with `Deinit`, and verifying the existence of
/// any files indicated in the return value.
pub fn Parse(alloc: Allocator) !CLI {
    var i_kind: ?IOKind = null;
    var o_kind: ?IOKind = null;
    var i_file: []const u8 = &[_]u8{};
    var o_file: []const u8 = &[_]u8{};
    var b_allow_tty = false;
    var b_show_help = false;
    var b_io_file_same = false;
    var fmt = FormatSettings{};

    var waiters = std.mem.zeroes(Waiters);

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.next();
    while (args.next()) |arg| {
        const fo = EnumCheckOnce(arg, &.{"-fo"}, IOKind, .File, &o_kind);
        if (StageTwoCheck(alloc, arg, fo, []const u8, &o_file, &waiters.fo))
            continue;
        if (EnumCheckOnce(arg, &.{"-co"}, IOKind, .Console, &o_kind))
            continue;

        if (BoolCheckOnce(arg, &.{ "-tty", "--allow-tty" }, &b_allow_tty))
            continue;

        if (BoolCheckOnce(arg, &.{ "-h", "--help" }, &b_show_help))
            break;

        const ts = RawCheck(arg, &.{ "-ts", "--tab-size" });
        if (StageTwoCheck(alloc, arg, ts, usize, &fmt.TabSize, &waiters.ts))
            continue;
        const mbl = RawCheck(arg, &.{ "-mbl", "--max-blank-lines" });
        if (StageTwoCheck(alloc, arg, mbl, usize, &fmt.MaxBlankLines, &waiters.mbl))
            continue;
        const tcc = RawCheck(arg, &.{ "-tcc", "--text-comment-column" });
        if (StageTwoCheck(alloc, arg, tcc, usize, &fmt.TextComCol, &waiters.tcc))
            continue;
        const tia = RawCheck(arg, &.{ "-tia", "--text-instruction-advance" });
        if (StageTwoCheck(alloc, arg, tia, usize, &fmt.TextInsMinAdv, &waiters.tia))
            continue;
        const toa = RawCheck(arg, &.{ "-toa", "--text-operands-advance" });
        if (StageTwoCheck(alloc, arg, toa, usize, &fmt.TextOpsMinAdv, &waiters.toa))
            continue;
        const dcc = RawCheck(arg, &.{ "-dcc", "--data-comment-column" });
        if (StageTwoCheck(alloc, arg, dcc, usize, &fmt.DataComCol, &waiters.dcc))
            continue;
        const dia = RawCheck(arg, &.{ "-dia", "--data-instruction-advance" });
        if (StageTwoCheck(alloc, arg, dia, usize, &fmt.DataInsMinAdv, &waiters.dia))
            continue;
        const doa = RawCheck(arg, &.{ "-doa", "--data-operands-advance" });
        if (StageTwoCheck(alloc, arg, doa, usize, &fmt.DataOpsMinAdv, &waiters.doa))
            continue;
        const sin = RawCheck(arg, &.{ "-sin", "--section-indent-none" });
        if (StageTwoCheck(alloc, arg, sin, usize, &fmt.SectionIndentNone, &waiters.sin))
            continue;
        const sid = RawCheck(arg, &.{ "-sid", "--section-indent-data" });
        if (StageTwoCheck(alloc, arg, sid, usize, &fmt.SectionIndentData, &waiters.sid))
            continue;
        const sit = RawCheck(arg, &.{ "-sit", "--section-indent-text" });
        if (StageTwoCheck(alloc, arg, sit, usize, &fmt.SectionIndentText, &waiters.sit))
            continue;
        const sio = RawCheck(arg, &.{ "-sio", "--section-indent-other" });
        if (StageTwoCheck(alloc, arg, sio, usize, &fmt.SectionIndentOther, &waiters.sio))
            continue;

        if (i_kind != null) break;
        i_kind = .File;
        i_file = try alloc.dupeZ(u8, arg);
    }

    if (waiters.AnyWaiting()) return CLIError.InvalidTwoPartArgument;

    if (i_kind == null) i_kind = .Console;
    if (o_kind == null) o_kind = i_kind;
    if (o_kind == .File and (o_file.len == 0 or eql(u8, i_file, o_file))) {
        o_file = try std.fmt.allocPrintZ(alloc, "{s}.tmp", .{i_file});
        b_io_file_same = true;
    }

    assert(i_kind != .File or i_file.len > 0);
    assert(o_kind != .File or o_file.len > 0);
    return CLI{
        .FmtSettings = fmt,
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
pub fn Deinit(self: *CLI, alloc: Allocator) void {
    alloc.free(self.IFile);
    alloc.free(self.OFile);
}

// helpers

// all helpers return whether they got a "hit" on a cli flag, indicating that the
// parsing loop can short circuit

/// parse argument as value to the previous argument
fn StageTwoCheck(
    alloc: Allocator,
    arg: []const u8,
    stage1_triggered: bool, // use result from your regular checker here
    comptime ValT: type,
    out: *ValT,
    b_waiting: *bool,
) bool {
    if (b_waiting.*) {
        switch (@typeInfo(ValT)) {
            .Pointer => |t| {
                comptime assert(t.is_const);
                comptime assert(t.child == u8);
                comptime assert(t.size == .Slice);
                out.* = alloc.dupeZ(u8, arg) catch out.*;
            },
            .Int => |t| {
                comptime assert(t.signedness == .unsigned);
                // overflow or wrong sign falls back to existing value
                out.* = std.fmt.parseUnsigned(ValT, arg, 0) catch out.*;
            },
            else => @compileError("unsupported type"),
        }
        b_waiting.* = false;
        return true;
    }

    b_waiting.* = stage1_triggered;
    return stage1_triggered;
}

/// sets a bool to true if argument matches any, skipping if the bool is already
/// set true
fn BoolCheckOnce(arg: []const u8, comptime flags: []const []const u8, out: *bool) bool {
    if (out.*) return false;
    inline for (flags) |flag| if (eql(u8, arg, flag)) {
        out.* = true;
        return true;
    };
    return false;
}

/// sets a nullable enum to a given value if argument matches any, skipping if
/// the enum is already set
fn EnumCheckOnce(arg: []const u8, comptime flags: []const []const u8, comptime T: type, val: T, out: *?T) bool {
    if (out.* != null) return false;
    inline for (flags) |flag| if (eql(u8, arg, flag)) {
        out.* = val;
        return true;
    };
    return false;
}

/// match an argument against a list of flags
fn RawCheck(arg: []const u8, comptime flags: []const []const u8) bool {
    inline for (flags) |flag|
        if (eql(u8, arg, flag)) return true;
    return false;
}
