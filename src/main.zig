const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub fn main() !void {
    var stdi = std.io.getStdIn();
    const stdi_br = std.io.bufferedReader(stdi.reader());
    var stdo = std.io.getStdOut();
    const stdo_bw = std.io.bufferedWriter(stdo.writer());
    defer stdo_bw.flush();

    try Format(stdi_br.reader(), stdo_bw.writer(), .{});
}

const Token = struct {
    token: enum(u8) { None, String, Comma, Semicolon, Whitespace, ScopeOpen, ScopeClose } = .None,
    data: []const u8 = &[_]u8{},
};

const LineMode = enum { Blank, Unknown, Comment, Source, Macro, AsmDirective, PreProcDirective };

// NOTE: assembler directives: 'primitive' directives enclosed in square brackets,
//  'user-level' directives are bare
// NOTE: see chapter 8 (p.101)
/// identifiers that can appear as first word on a directive line, including aliases
const AssemblerDirective = enum { bits, use16, use32, default, section, segment, absolute, @"extern", required, global, common, static, prefix, gprefix, lprefix, suffix, gsuffix, lsuffix, cpu, dollarhex, float, warning, list };

// TODO: ring buffer, to support line lookback
var ScrBufLine = std.mem.zeroes([4096]u8);
var TokBufLine = std.mem.zeroes([1024]Token);
var OutBufLine = std.mem.zeroes([4096]u8);

const FormatError = error{SourceContainsBOM};
const LineState = enum { Label, Instruction, Operands, Comment };

const FormatSettings = struct {
    TabSize: usize = 4,
    /// Comment column, when line is not a standalone comment.
    ComCol: usize = 40,
    /// Columns between start of label and instruction, rounded up to next multiple
    /// of TabSize. Lines without a label will ignore this setting and inset the
    /// instruction by TabSize.
    InsMinGap: usize = 12,
    /// Columns between start of instruction and start of operands, rounded up to
    /// the next multiple of TabSize.
    OpsMinGap: usize = 8,
};

// NOTE: logic based on chapter 3, 5 and 8 of the NASM documentation, with some
//  compromises for the sake of practicality
/// @i      Reader to NASM source code, in a UTF-8 compatible byte stream
/// @o      Writer to the formatted code's destination byte stream
pub fn Format(
    in: anytype,
    out: anytype,
    settings: FormatSettings,
) FormatError!void {
    var line = std.ArrayListUnmanaged(u8).initBuffer(&OutBufLine);
    var line_tok = std.ArrayListUnmanaged(Token).initBuffer(&TokBufLine);

    const line_ctx: LineContext = .{
        .ColCom = settings.ComCol,
        .ColIns = settings.TabSize,
        .ColOps = settings.TabSize + settings.OpsMinGap,
        .ColLabIns = settings.InsMinGap,
        .ColLabOps = settings.InsMinGap + settings.OpsMinGap,
    };

    // FIXME: handle line read error
    var line_i: usize = 0;
    while (in.readUntilDelimiterOrEof(&ScrBufLine, '\n') catch unreachable) |line_s| : (line_i += 1) {
        if (line_i == 0 and std.mem.startsWith(u8, line_s, &[3]u8{ 0xEF, 0xBB, 0xBF }))
            return error.SourceContainsBOM;

        // TODO: check line is valid utf-8 before all else, and just emit the
        //  line without any processing if not

        const b_crlf: bool, const body: []const u8, const comment: []const u8 = comgen: {
            var b_crlf = false;
            var body_s = line_s[0..];
            var com_s = line_s[line_s.len..];

            if (std.mem.endsWith(u8, body_s, "\r")) {
                body_s = body_s[0 .. body_s.len - 1];
                b_crlf = true;
            }

            var scope: ?u8 = null;
            var escaped = false;
            for (body_s, 0..) |c, i| {
                var will_escape = false;
                defer escaped = will_escape;
                switch (c) {
                    '\\' => {
                        if (scope != null and !escaped)
                            will_escape = true;
                    },
                    '\"', '\'' => {
                        if (scope) |s| {
                            if (s == c and !escaped) scope = null;
                            continue;
                        }
                        scope = c;
                    },
                    ';' => if (scope == null) {
                        com_s = body_s[i..];
                        body_s = body_s[0..i];
                        break;
                    },
                    else => {},
                }
            }

            break :comgen .{ b_crlf, std.mem.trim(u8, body_s, "\t "), com_s };
        };

        var tokgen_it = std.unicode.Utf8Iterator{ .bytes = body, .i = 0 };
        tokgen: while (true) {
            const start_i = tokgen_it.i;
            const c = tokgen_it.nextCodepoint() orelse break :tokgen;
            var token: *Token = line_tok.addOneAssumeCapacity();
            switch (c) {
                ',' => {
                    token.token = .Comma;
                    token.data = body[start_i..tokgen_it.i];
                },
                ';' => {
                    token.token = .Semicolon;
                    token.data = body[start_i..tokgen_it.i];
                },
                '(', '[', '{' => {
                    token.token = .ScopeOpen;
                    token.data = body[start_i..tokgen_it.i];
                },
                ')', ']', '}' => {
                    token.token = .ScopeClose;
                    token.data = body[start_i..tokgen_it.i];
                },
                ' ', '\t' => {
                    token.token = .Whitespace;
                    while (true) {
                        const peek_s = tokgen_it.peek(1);
                        if (peek_s.len == 0 or
                            (peek_s.len == 1 and std.mem.indexOfScalar(u8, " \t", peek_s[0]) == null))
                            break;
                        _ = tokgen_it.nextCodepoint();
                    }
                    token.data = body[start_i..tokgen_it.i];
                },
                else => {
                    token.token = .String;
                    while (true) {
                        const peek_s = tokgen_it.peek(1);
                        if (peek_s.len == 0 or
                            (peek_s.len == 1 and std.mem.indexOfScalar(u8, ",; \t([{}])", peek_s[0]) != null))
                            break;
                        _ = tokgen_it.nextCodepoint();
                    }
                    token.data = body[start_i..tokgen_it.i];
                },
            }
        }

        const line_mode: LineMode = mode: {
            if (line_tok.items.len == 0)
                break :mode .Blank;

            const first = &line_tok.items[0];
            var case_buf: [64]u8 = undefined;

            break :mode switch (first.token) {
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
                .ScopeOpen => if (first.data[0] == '[') .AsmDirective else .Unknown,
                .Semicolon => .Comment,
                .Whitespace => unreachable, // token sequence should be pre-stripped
                else => .Unknown,
            };
        };

        // FIXME: give this real logic lol
        switch (line_mode) {
            .AsmDirective => {
                // TODO: actually format this properly; need to format differently
                //  for 'primitive'-type directives
                var case_buf: [12]u8 = undefined;
                const case = std.ascii.lowerString(&case_buf, line_tok.items[0].data);
                line.appendSliceAssumeCapacity(case);

                for (line_tok.items[1..]) |tok| {
                    switch (tok.token) {
                        .Whitespace => line.appendAssumeCapacity(' '),
                        .Comma => line.appendSliceAssumeCapacity(", "),
                        else => line.appendSliceAssumeCapacity(tok.data),
                    }
                }
            },
            .PreProcDirective => {
                var case_buf: [12]u8 = undefined;
                const case = std.ascii.lowerString(&case_buf, line_tok.items[0].data);
                line.appendSliceAssumeCapacity(case);

                for (line_tok.items[1..]) |tok| {
                    switch (tok.token) {
                        .Whitespace => line.appendAssumeCapacity(' '),
                        .Comma => line.appendSliceAssumeCapacity(", "),
                        else => line.appendSliceAssumeCapacity(tok.data),
                    }
                }
            },
            .Macro => {
                var case_buf: [12]u8 = undefined;
                const case = std.ascii.lowerString(&case_buf, line_tok.items[0].data);
                line.appendSliceAssumeCapacity(case);

                for (line_tok.items[1..]) |tok| {
                    switch (tok.token) {
                        .Whitespace => line.appendAssumeCapacity(' '),
                        .Comma => line.appendSliceAssumeCapacity(", "),
                        else => line.appendSliceAssumeCapacity(tok.data),
                    }
                }
            },
            .Source => FormatSourceLine(&line_tok, &line, &line_ctx),
            else => {},
        }

        // NOTE: assumes the comment slice will contain the leading semicolon
        // FIXME: base on number of utf8 codepoints, not byte length of `line`
        if (comment.len > 0) {
            const pad_n: usize = @max(1, line_ctx.ColCom -| line.items.len);
            line.appendNTimesAssumeCapacity(32, pad_n);
            line.appendSliceAssumeCapacity(comment);
        }

        _ = out.write(line.items) catch unreachable; // FIXME: handle
        _ = out.write(if (b_crlf) "\r\n" else "\n") catch unreachable; // FIXME: handle

        line.clearRetainingCapacity();
        line_tok.clearRetainingCapacity();
    }
}

const LineContext = struct {
    ColCom: usize, // column: comment
    ColIns: usize, // column: instruction
    ColOps: usize, // column: operands
    ColLabIns: usize, // column: instruction (with label present)
    ColLabOps: usize, // column: operands (with label present)
};

// FIXME: pathological lack of bounds checking and assuming that there will be a
//  next token or chunk
// TODO: take tokens as a slice?
/// takes a token list representing a "normal" nasm source line, and writes out
/// the formatted results to a buffer
/// @tok    tokenized source line, in the format produced by Token-related code
/// @out    buffer must be empty for correct formatting
fn FormatSourceLine(
    tok: *std.ArrayListUnmanaged(Token),
    out: *std.ArrayListUnmanaged(u8),
    ctx: *const LineContext,
) void {
    var b_label = false;
    var b_state_initialized = false;
    var line_state: LineState = .Label;

    var fmtgen_ci: usize = 0; // utf-8 codepoints pushed
    var fmtgen_i: usize = 0;
    fmtgen: while (true) {
        if (fmtgen_i >= tok.items.len) break :fmtgen;
        line_state = switch (line_state) {
            .Label => ls: {
                const next_s: LineState = if (std.mem.endsWith(u8, tok.items[fmtgen_i].data, ":")) st: {
                    b_label = true;
                    break :st .Instruction;
                } else st: { // if not followed by ':', assume it's an instruction
                    TokPadSpaces(out, &fmtgen_ci, ctx.ColIns);
                    break :st .Operands;
                };
                TokAppend(out, tok.items, &fmtgen_i, &fmtgen_ci);
                break :ls TokEndLinePart(&b_state_initialized, next_s);
            },
            .Instruction => ls: {
                if (!b_state_initialized) {
                    b_state_initialized = true;
                    TokPadSpaces(out, &fmtgen_ci, if (b_label) ctx.ColLabIns else ctx.ColIns);
                }
                TokSkipWhitespace(tok.items, &fmtgen_i);
                TokAppend(out, tok.items, &fmtgen_i, &fmtgen_ci);
                break :ls TokEndLinePart(&b_state_initialized, .Operands);
            },
            .Operands => ls: {
                if (!b_state_initialized) {
                    b_state_initialized = true;
                    TokPadSpaces(out, &fmtgen_ci, if (b_label) ctx.ColLabOps else ctx.ColOps);
                }
                TokSkipWhitespace(tok.items, &fmtgen_i);
                while (tok.items.len > fmtgen_i) {
                    if (tok.items[fmtgen_i].token == .Comma) {
                        TokAppendStr(out, &fmtgen_ci, ", ");
                        fmtgen_i += 1;
                    } else {
                        TokAppend(out, tok.items, &fmtgen_i, &fmtgen_ci);
                    }
                }
                break :ls TokEndLinePart(&b_state_initialized, .Comment);
            },
            // input stream should be done by this point, comment printing will
            // be handled externally
            .Comment => unreachable,
        };
    }
}

// HELPERS

fn TokSkipWhitespace(tok: []const Token, ti: *usize) void {
    var i = ti.*;
    while (i < tok.len and tok[i].token == .Whitespace)
        i += 1;
    ti.* = i;
}

fn TokPadSpaces(line: *std.ArrayListUnmanaged(u8), col: *usize, until: usize) void {
    const n: usize = @max(1, until -| col.*);
    line.appendNTimesAssumeCapacity(32, n);
    col.* += n;
}

fn TokEndLinePart(next_initialized: *bool, next_state: LineState) LineState {
    next_initialized.* = false;
    return next_state;
}

fn TokAppend(line: *std.ArrayListUnmanaged(u8), tok: []const Token, i: *usize, ci: *usize) void {
    line.appendSliceAssumeCapacity(tok[i.*].data);
    ci.* += std.unicode.utf8CountCodepoints(tok[i.*].data) catch unreachable;
    i.* += 1;
}

fn TokAppendStr(line: *std.ArrayListUnmanaged(u8), ci: *usize, str: []const u8) void {
    line.appendSliceAssumeCapacity(str);
    ci.* += str.len;
}

// TESTING

// NOTE: see annodue x86 util for testing setup reference
// TODO: FormatSettings as input in FormatTestCase
// TODO: probably migrate most of this to individual line component tests in
//  future, although some are more generic (e.g. BOM test); also real end-to-end
//  test should pull in source files at comptime?
test "initial test to get things going plis rework/rename this later or else bro" {
    const FormatTestCase = struct {
        in: []const u8,
        ex: []const u8 = &[_]u8{},
        err: ?FormatError = null,
    };
    const test_cases = [_]FormatTestCase{
        .{ // BOM
            .in = &[_]u8{ 0xEF, 0xBB, 0xBF } ++ " \t  my_label: mov eax,16; comment",
            .err = error.SourceContainsBOM,
        },
        .{ // line with all 4
            .in = " \t  my_label: mov eax,16; comment",
            .ex = "my_label:   mov     eax, 16             ; comment\n",
        },
        .{ // no label
            .in = " \t  mov  eax,16; comment",
            .ex = "    mov     eax, 16                     ; comment\n",
        },
        // NOTE: curiously, this passes whether or not the input has a trailing
        //  newline
        .{ // multiline with lone "label header"
            .in =
            \\    my_label:
            \\mov eax,16; comment
            ,
            .ex =
            \\my_label:
            \\    mov     eax, 16                     ; comment
            \\
            ,
        },
        .{ // multiline with crlf break
            .in = "  my_label:\r\nmov eax,16; comment",
            .ex = "my_label:\r\n    mov     eax, 16                     ; comment\n",
        },
        .{ // double multiline
            .in = "  my_label:\n\nmov eax,16; comment",
            .ex = "my_label:\n\n    mov     eax, 16                     ; comment\n",
        },
        .{ // double multiline crlf
            .in = "  my_label:\r\n\r\nmov eax,16; comment",
            .ex = "my_label:\r\n\r\n    mov     eax, 16                     ; comment\n",
        },
        .{ // %macro (case-insensitive)
            .in = "%mACRO CoolMacro 2",
            .ex = "%macro CoolMacro 2\n",
        },
        .{ // %imacro (case-insensitive)
            .in = "%IMAcro CoolMacro 2",
            .ex = "%imacro CoolMacro 2\n",
        },
        .{ // %endmacro (case-insensitive)
            .in = "%enDMACro",
            .ex = "%endmacro\n",
        },
        .{ // extern (assembler directive)
            .in = "extern _SomeFunctionName@12",
            .ex = "extern _SomeFunctionName@12\n",
        },
        .{ // misc preprocessor directive
            .in = "%pragma    something",
            .ex = "%pragma something\n",
        },
        .{ // comment detection
            .in = "string  db \"Atta'c'h;Console Failed!\",0; comment",
            .ex = "    string  db \"Atta'c'h;Console Failed!\", 0 ; comment\n",
        },
    };

    std.testing.log_level = .debug;
    for (test_cases, 0..) |t, i| {
        errdefer std.debug.print("FAILED {d:0>2}\n\n", .{i});

        var input = std.io.fixedBufferStream(t.in);
        var output = std.ArrayList(u8).init(std.testing.allocator);
        defer output.deinit();

        const f = Format(input.reader(), output.writer(), .{});
        if (t.err) |ex_err| {
            try std.testing.expectError(ex_err, f);
        } else {
            try std.testing.expectEqualStrings(t.ex, output.items);
            try std.testing.expectEqual(t.ex.len, output.items.len);
        }
    }
}
