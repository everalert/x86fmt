//! Reads settings from the command line. Arguments can be provided in any order
//! and will short-circuit if repeated.
//!
//! Settings provided by this module:
//! - Input mode; defaults to stdin
//! - Output mode; defaults to matching the input setting
//! - Input file; set input to File mode by providing a file path
//! - Output file; will overwrite input file, unless output file specified
//! - Show Help flag
//!
//! The following flags are supported:
//!     <file>              Set input mode to File, reading from <file>
//!     -fo <file>          Set output mode to File, writing to <file>
//!     -co                 Set output mode to Console (stdout)
//!     -h, --help          Display help information (not yet implemented)
//!
//! Sample usage:
//!     x86fmt (none)                       input: <stdin>    output: <stdout>
//!     x86fmt source.s                     input: source.s   output: source.s
//!     x86fmt source.s -co                 input: source.s   output: <stdout>
//!     x86fmt source.s -fo output.s        input: source.s   output: output.s
//!     x86fmt -fo output.s                 input: <stdin>    output: output.s
//!     x86fmt -fo                          invalid
const CLI = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const eql = std.mem.eql;

// TODO: add help text (don't forget to update docs comment above)
// TODO: add tests. may need to rework input mechanism for testability, since
//  Parse reads the process arguments directly.

pub const IOKind = enum { Console, File };
pub const CLIError = error{OutputFileUnknown};

bShowHelp: bool,
/// implies that IKind and OKind are both File. if true, OFile will match IFile
/// but with ".tmp" appended; after formatting, the caller can simply delete
/// IFile and rename OFile in response to this being true.
bIOFileSame: bool, // if true,
IKind: IOKind,
OKind: IOKind,
IFile: []const u8,
OFile: []const u8,

/// Parse command line arguments and generate a CLI settings object.
pub fn Parse(alloc: Allocator) !CLI {
    var i_kind: ?IOKind = null;
    var o_kind: ?IOKind = null;
    var i_file: []const u8 = &[_]u8{};
    var o_file: []const u8 = &[_]u8{};
    var b_show_help = false;
    var b_io_file_same = false;

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    var b_awaiting_output_file = false;
    var b_first_skipped = false;

    while (args.next()) |arg| {
        var b_output_file_flag = false;
        defer b_awaiting_output_file = b_output_file_flag;

        if (!b_first_skipped) {
            b_first_skipped = true;
            continue;
        }

        if (b_awaiting_output_file) {
            o_file = try alloc.dupeZ(u8, arg);
            continue;
        }

        if (o_kind == null and eql(u8, arg, "-co")) {
            o_kind = .Console;
            continue;
        }

        if (o_kind == null and eql(u8, arg, "-fo")) {
            o_kind = .File;
            b_output_file_flag = true;
            continue;
        }

        if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
            b_show_help = true;
            break;
        }

        i_kind = .File;
        i_file = try alloc.dupeZ(u8, arg);
    }

    if (b_awaiting_output_file)
        return CLIError.OutputFileUnknown;

    if (i_kind == null) i_kind = .Console;
    if (o_kind == null) o_kind = i_kind;
    if (o_kind == .File and o_file.len == 0) {
        o_file = try std.fmt.allocPrintZ(alloc, "{s}.tmp", .{i_file});
        b_io_file_same = true;
    }

    assert(i_kind != .File or i_file.len > 0);
    assert(o_kind != .File or o_file.len > 0);
    return CLI{
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
