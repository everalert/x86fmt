const Line = @This();

const std = @import("std");
const assert = std.debug.assert;

const Token = @import("token.zig");

pub const State = enum { Label, Instruction, Operands, Comment };

pub const Mode = enum { Blank, Unknown, Comment, Source, Macro, AsmDirective, PreProcDirective };

pub const Context = struct {
    ColCom: usize, // column: comment
    ColIns: usize, // column: instruction
    ColOps: usize, // column: operands
    ColLabIns: usize, // column: instruction (with label present)
    ColLabOps: usize, // column: operands (with label present)
};

// NOTE: assembler directives: 'primitive' directives enclosed in square brackets,
//  'user-level' directives are bare
// NOTE: see chapter 8 (p.101)
/// identifiers that can appear as first word on a directive line, including aliases
const AssemblerDirective = enum {
    // zig fmt: off
    bits, use16, use32, default, section, segment, absolute, @"extern", 
    required, global, common, static, prefix, gprefix, lprefix, suffix, 
    gsuffix, lsuffix, cpu, dollarhex, float, warning, list 
    // zig fmt: on
};

// FIXME: base this on lexemes?
pub fn ParseMode(tok: []const Token) Mode {
    if (tok.len == 0)
        return .Blank;

    const first = &tok[0];
    var case_buf: [64]u8 = undefined;

    return switch (first.kind) {
        .String => str: {
            const lowercase = std.ascii.lowerString(&case_buf, first.data);

            const macro_names = [_][]const u8{ "%macro", "%endmacro", "%imacro" };
            for (macro_names) |mn| {
                if (mn.len != first.data.len)
                    continue;

                if (std.mem.eql(u8, mn, lowercase))
                    break :str .Macro;
            }

            if (first.data[0] == '%')
                break :str .PreProcDirective;

            if (std.meta.stringToEnum(AssemblerDirective, lowercase) != null)
                break :str .AsmDirective;

            break :str .Source;
        },
        .Scope => if (first.data[0] == '[') .AsmDirective else .Unknown,
        .Whitespace => unreachable, // token sequence should be pre-stripped
        else => .Unknown,
    };
}
