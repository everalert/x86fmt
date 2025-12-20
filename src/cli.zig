//! Reads settings from the command line. Arguments can be provided in any order
//! and will short-circuit if repeated.
//!
//! Settings provided by this module:
//! - Input mode; defaults to stdin
//! - Output mode; defaults to matching the input setting
//! - Input file; set input to File mode by providing a file path
//! - Output file; will overwrite input file, unless output file specified
//! - Show Help flag
//! - Configuration of formatting values (comment column, etc.)
//!
//! The following flags are supported:
//!     <file>              input mode = File, reading from <file>
//!     -fo <file>          output mode = File, writing to <file>
//!     -co                 output mode = Console (stdout)
//!     -h, --help          display help information // FIXME: not yet written
//!     -tty, --allow-tty   accept console input for stdin (default off)
//!     -ts <num>,  --tab-size <num>                    default 4
//!     -mbl <num>, --max-blank-lines <num>             default 2
//!     -cc <num>,  --comment-col <num>                 default 40
//!     -img <num>, --instruction-min-gap <num>         default 12
//!     -omg <num>, --operands-min-gap <num>            default 8
//!     -dcc <num>, --data-comment-col <num>            default 64
//!     -dimg <num>, --data-instruction-min-gap <num>   default 16
//!     -domg <num>, --data-operands-min-gap <num>      default 32
//!     -sin <num>, --section-indent-none <num>         default 0
//!     -sid <num>, --section-indent-data <num>         default 0
//!     -sit <num>, --section-indent-text <num>         default 0
//!     -sio <num>, --section-indent-other <num>        default 0
//!
//! Sample usage:
//!     x86fmt (none)                       input: <stdin>    output: <stdout>
//!     x86fmt source.s                     input: source.s   output: source.s
//!     x86fmt source.s -co                 input: source.s   output: <stdout>
//!     x86fmt source.s -fo output.s        input: source.s   output: output.s
//!     x86fmt -fo output.s                 input: <stdin>    output: output.s
//!     x86fmt -fo                          invalid
//!     x86fmt source.s -co -ts 2           input: source.s   output: <stdout>   tab size 2
const CLI = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const eql = std.mem.eql;

const FormatSettings = @import("format.zig").Settings;

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

// TODO: add help text (don't forget to update docs comment above)
// TODO: add tests. may need to rework input mechanism for testability, since
//  Parse reads the process arguments directly.

/// Parse command line arguments and generate a CLI settings object.
pub fn Parse(alloc: Allocator) !CLI {
    var i_kind: ?IOKind = null;
    var o_kind: ?IOKind = null;
    var i_file: []const u8 = &[_]u8{};
    var o_file: []const u8 = &[_]u8{};
    var b_allow_tty = false;
    var b_show_help = false;
    var b_io_file_same = false;
    var fmt = FormatSettings{};

    var b_ts_waiter = false;
    var b_mbl_waiter = false;
    var b_cc_waiter = false;
    var b_img_waiter = false;
    var b_omg_waiter = false;
    var b_dcc_waiter = false;
    var b_dimg_waiter = false;
    var b_domg_waiter = false;
    var b_sin_waiter = false;
    var b_sid_waiter = false;
    var b_sit_waiter = false;
    var b_sio_waiter = false;
    var b_fo_waiter = false;

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.next();
    while (args.next()) |arg| {
        const ts = RawCheck(arg, &.{ "-ts", "--tab-size" });
        if (StageTwoCheck(alloc, arg, ts, usize, &fmt.TabSize, &b_ts_waiter))
            continue;
        const mbl = RawCheck(arg, &.{ "-mbl", "--max-blank-lines" });
        if (StageTwoCheck(alloc, arg, mbl, usize, &fmt.MaxBlankLines, &b_mbl_waiter))
            continue;
        const cc = RawCheck(arg, &.{ "-cc", "--comment-column" });
        if (StageTwoCheck(alloc, arg, cc, usize, &fmt.ComCol, &b_cc_waiter))
            continue;
        const img = RawCheck(arg, &.{ "-img", "--instruction-min-gap" });
        if (StageTwoCheck(alloc, arg, img, usize, &fmt.InsMinGap, &b_img_waiter))
            continue;
        const omg = RawCheck(arg, &.{ "-omg", "--operands-min-gap" });
        if (StageTwoCheck(alloc, arg, omg, usize, &fmt.OpsMinGap, &b_omg_waiter))
            continue;
        const dcc = RawCheck(arg, &.{ "-dcc", "--data-comment-column" });
        if (StageTwoCheck(alloc, arg, dcc, usize, &fmt.DataComCol, &b_dcc_waiter))
            continue;
        const dimg = RawCheck(arg, &.{ "-dimg", "--data-instruction-min-gap" });
        if (StageTwoCheck(alloc, arg, dimg, usize, &fmt.DataInsMinGap, &b_dimg_waiter))
            continue;
        const domg = RawCheck(arg, &.{ "-domg", "--data-operands-min-gap" });
        if (StageTwoCheck(alloc, arg, domg, usize, &fmt.DataOpsMinGap, &b_domg_waiter))
            continue;
        const sin = RawCheck(arg, &.{ "-sin", "--section-indent-none" });
        if (StageTwoCheck(alloc, arg, sin, usize, &fmt.SectionIndentNone, &b_sin_waiter))
            continue;
        const sid = RawCheck(arg, &.{ "-sid", "--section-indent-data" });
        if (StageTwoCheck(alloc, arg, sid, usize, &fmt.SectionIndentData, &b_sid_waiter))
            continue;
        const sit = RawCheck(arg, &.{ "-sit", "--section-indent-text" });
        if (StageTwoCheck(alloc, arg, sit, usize, &fmt.SectionIndentText, &b_sit_waiter))
            continue;
        const sio = RawCheck(arg, &.{ "-sio", "--section-indent-other" });
        if (StageTwoCheck(alloc, arg, sio, usize, &fmt.SectionIndentOther, &b_sio_waiter))
            continue;

        const fo = EnumCheckOnce(arg, &.{"-fo"}, IOKind, .File, &o_kind);
        if (StageTwoCheck(alloc, arg, fo, []const u8, &o_file, &b_fo_waiter))
            continue;
        if (EnumCheckOnce(arg, &.{"-co"}, IOKind, .Console, &o_kind))
            continue;

        if (BoolCheckOnce(arg, &.{ "-tty", "--allow-tty" }, &b_allow_tty))
            continue;

        if (BoolCheckOnce(arg, &.{ "-h", "--help" }, &b_show_help))
            break;

        if (i_kind != null) break;
        i_kind = .File;
        i_file = try alloc.dupeZ(u8, arg);
    }

    const b_any_waiting = (@intFromBool(b_fo_waiter) | @intFromBool(b_ts_waiter) | @intFromBool(b_cc_waiter) |
        @intFromBool(b_img_waiter) | @intFromBool(b_omg_waiter) | @intFromBool(b_mbl_waiter)) > 0;
    if (b_any_waiting) return CLIError.InvalidTwoPartArgument;

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
