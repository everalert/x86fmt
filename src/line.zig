const Line = @This();

const std = @import("std");
const assert = std.debug.assert;

const FormatSettings = @import("format.zig").Settings;
const Lexeme = @import("lexeme.zig");
const Token = @import("token.zig");
const BLOR = @import("util.zig").BLOR;

pub const State = enum { Label, Instruction, Operands, Comment };

pub const Mode = enum { Blank, Unknown, Comment, Source, Macro, AsmDirective, PreProcDirective };

// FIXME: should the line buffers be ref'd here?
pub const Context = struct {
    Mode: Mode,
    Section: SectionKind,
    ColLab: usize, // column: label
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

const MacroNames = [_][]const u8{ "%macro", "%endmacro", "%imacro" };

const SectionKind = enum { None, Text, Data, Other };

// ELF: https://man7.org/linux/man-pages/man5/elf.5.html (search 'bss')
// PE: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#special-sections
const SectionDataSuffixes = [_][]const u8{ "bss", "data", "tls" }; // also: data1, tls$
const SectionTextSuffixes = [_][]const u8{"text"}; // yep

pub fn CtxParseMode(
    ctx: *Context,
    lex: []const Lexeme,
    comptime BUF_SIZE_TOK: usize,
) void {
    if (lex.len == 0) {
        ctx.Mode = .Blank;
        return;
    }

    var case_buf: [BUF_SIZE_TOK]u8 = undefined;

    const tok = &lex[0].data[0];
    ctx.Mode = switch (tok.kind) {
        .String => str: {
            const lowercase = std.ascii.lowerString(&case_buf, tok.data);

            for (MacroNames) |mn| {
                if (mn.len != tok.data.len)
                    continue;

                if (std.mem.eql(u8, mn, lowercase))
                    break :str .Macro;
            }

            if (tok.data[0] == '%')
                break :str .PreProcDirective;

            if (std.meta.stringToEnum(AssemblerDirective, lowercase) != null)
                break :str .AsmDirective;

            break :str .Source;
        },
        .Scope => if (tok.data[0] == '[') .AsmDirective else .Unknown,
        .Whitespace => unreachable, // token sequence should be pre-stripped
        else => .Unknown,
    };
}

pub fn CtxUpdateSection(
    ctx: *Context,
    lex: []const Lexeme,
    fmt: *const FormatSettings,
    comptime BUF_SIZE_TOK: usize,
) void {
    if (ctx.Mode != .AsmDirective) return;
    var case_buf: [BUF_SIZE_TOK]u8 = undefined;

    // detect section context
    const tok1, const tok2 = tokens: {
        const d1 = lex[0].data;
        if (d1[0].kind == .Scope) {
            if (d1.len < 3 or
                BLOR(d1[1].kind != .String, d1[2].kind != .String))
                return;
            break :tokens .{ &d1[1], &d1[2] };
        }
        const d2 = lex[1].data;
        if (lex.len < 2) return;
        if (lex.len < 2 or
            BLOR(d1[0].kind != .String, d2[0].kind != .String))
            return;
        break :tokens .{ &d1[0], &d2[0] };
    };

    const directive = std.ascii.lowerString(&case_buf, tok1.data);
    if (!std.mem.eql(u8, directive, "section")) return;

    defer CtxUpdateColumns(ctx, fmt);

    const section = std.ascii.lowerString(&case_buf, tok2.data);
    if (!std.mem.startsWith(u8, section, ".")) {
        ctx.Section = .Other;
        return;
    }
    for (SectionTextSuffixes) |suf| if (std.mem.endsWith(u8, section, suf)) {
        ctx.Section = .Text;
        return;
    };
    for (SectionDataSuffixes) |suf| if (std.mem.endsWith(u8, section, suf)) {
        ctx.Section = .Data;
        return;
    };
}

pub fn CtxUpdateColumns(ctx: *Context, fmt: *const FormatSettings) void {
    switch (ctx.Section) {
        .Data => {
            const base = fmt.SectionIndentData;
            ctx.ColLab = base;
            ctx.ColCom = fmt.DataComCol;
            ctx.ColIns = base + fmt.TabSize;
            ctx.ColOps = base + fmt.TabSize + fmt.DataOpsMinGap;
            ctx.ColLabIns = base + fmt.DataInsMinGap;
            ctx.ColLabOps = base + fmt.DataInsMinGap + fmt.DataOpsMinGap;
        },
        else => |s| {
            const base = switch (s) {
                .None => fmt.SectionIndentNone,
                .Text => fmt.SectionIndentText,
                .Other => fmt.SectionIndentOther,
                else => unreachable,
            };
            ctx.ColLab = base;
            ctx.ColCom = fmt.ComCol;
            ctx.ColIns = base + fmt.TabSize;
            ctx.ColOps = base + fmt.TabSize + fmt.OpsMinGap;
            ctx.ColLabIns = base + fmt.InsMinGap;
            ctx.ColLabOps = base + fmt.InsMinGap + fmt.OpsMinGap;
        },
    }
}
