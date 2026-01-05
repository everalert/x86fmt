const Line = @This();

const std = @import("std");
const assert = std.debug.assert;

const FormatSettings = @import("fmt_settings.zig");
const Lexeme = @import("fmt_lexeme.zig");
const Token = @import("fmt_token.zig");
const BLOR = @import("utl_branchless.zig").BLOR;
const BLSELE = @import("utl_branchless.zig").BLSELE;

pub const State = enum { Label, Instruction, Operands, Comment };

pub const Mode = enum { Blank, Unknown, Comment, Source, Macro, AsmDirective, PreProcDirective };

pub const Context = struct {
    Mode: Mode,
    Section: SectionKind,
    ColLab: usize, // column: label
    ColCom: usize, // column: comment
    ColIns: usize, // column: instruction
    ColOps: usize, // column: operands
    ColLabIns: usize, // column: instruction (with label present)
    ColLabOps: usize, // column: operands (with label present)
    NewLineStr: []const u8,
    ActualColCom: usize, // the column that the comment actually ended up being written to
    ActualColFirst: usize, // the first non-whitespace column

    pub const default: Context = .{
        .Mode = .Blank,
        .Section = .None,
        .ColLab = 0,
        .ColCom = 0,
        .ColIns = 0,
        .ColOps = 0,
        .ColLabIns = 0,
        .ColLabOps = 0,
        .NewLineStr = &.{},
        .ActualColCom = 0,
        .ActualColFirst = 0,
    };
};

// NOTE: assembler directives: 'primitive' directives enclosed in square brackets,
//  'user-level' directives are bare
// NOTE: see chapter 8 (p.101)
/// identifiers that can appear as first word on a directive line, including aliases
const AssemblerDirective = enum {
    // zig fmt: off
    bits, use16, use32, default, section, segment, absolute, @"extern",
    required, global, common, static, prefix, gprefix, lprefix, suffix,
    gsuffix, lsuffix, cpu, dollarhex, float, warning, list,
    // zig fmt: on

    pub fn AnyEqlIgnoreCase(cmp: []const u8) bool {
        inline for (std.meta.fields(AssemblerDirective)) |f| {
            if (std.ascii.eqlIgnoreCase(f.name, cmp)) return true;
        }
        return false;
    }
};

const MacroNames = [_][]const u8{ "%macro", "%endmacro", "%imacro" };

const SectionKind = enum { None, Text, Data, Other };

// ELF: https://man7.org/linux/man-pages/man5/elf.5.html (search 'bss')
// PE: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#special-sections
const SectionDataSuffixes = [_][]const u8{ "bss", "data", "tls" }; // also: data1, tls$
const SectionTextSuffixes = [_][]const u8{"text"}; // yep

// FIXME: for future: logic here belongs in parser, this should just switch
//  purely on token/node kind
pub fn CtxParseMode(
    ctx: *Context,
    lex: []const Lexeme,
) void {
    if (lex.len == 0) {
        ctx.Mode = .Blank;
        return;
    }

    const tok = &lex[0].data[0];

    ctx.Mode = switch (tok.kind) {
        .String => str: {
            for (MacroNames) |mn| {
                if (mn.len != tok.data.len)
                    continue;

                if (std.ascii.eqlIgnoreCase(mn, tok.data))
                    break :str .Macro;
            }

            if (tok.data[0] == '%')
                break :str .PreProcDirective;

            if (AssemblerDirective.AnyEqlIgnoreCase(tok.data))
                break :str .AsmDirective;

            break :str .Source;
        },
        .Scope => BLSELE(tok.data[0] == '[', Mode, .AsmDirective, .Unknown),
        .None, .Comment, .Backslash, .Comma, .MathOp => .Unknown,
    };
}

pub fn CtxUpdateSection(
    ctx: *Context,
    lex: []const Lexeme,
    fmt: *const FormatSettings,
) void {
    if (ctx.Mode != .AsmDirective) return;

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

    // FIXME: token size should still be pervasively asserted as < 4096 due to
    //  NASM requirements, need to check other places appropriate to assert
    assert(tok1.data.len < 4096);
    assert(tok2.data.len < 4096);

    if (!std.ascii.eqlIgnoreCase(tok1.data, "section")) return;

    defer CtxUpdateColumns(ctx, fmt);

    for (SectionTextSuffixes) |suf| if (std.ascii.endsWithIgnoreCase(tok2.data, suf)) {
        ctx.Section = .Text;
        return;
    };
    for (SectionDataSuffixes) |suf| if (std.ascii.endsWithIgnoreCase(tok2.data, suf)) {
        ctx.Section = .Data;
        return;
    };

    ctx.Section = .Other;
}

pub fn CtxUpdateColumns(ctx: *Context, fmt: *const FormatSettings) void {
    const base = switch (ctx.Section) {
        .None => fmt.SecIndentNone,
        .Text => fmt.SecIndentText,
        .Other => fmt.SecIndentOther,
        .Data => fmt.SecIndentData,
    };
    const com_col, const ops_min_adv, const ins_min_adv = switch (ctx.Section) {
        .Data, .None => .{ fmt.DataComCol, fmt.DataOpsMinAdv, fmt.DataInsMinAdv },
        .Text, .Other => .{ fmt.TextComCol, fmt.TextOpsMinAdv, fmt.TextInsMinAdv },
    };
    ctx.ColLab = base;
    ctx.ColCom = com_col;
    ctx.ColIns = base + fmt.TabSize;
    ctx.ColOps = base + fmt.TabSize + ops_min_adv;
    ctx.ColLabIns = base + ins_min_adv;
    ctx.ColLabOps = base + ins_min_adv + ops_min_adv;
}

// FIXME: add tests
//  - CtxParseMode
//  - CtxUpdateSection
//  - probably not necessary to test CtxUpdateColumns?
