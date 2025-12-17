const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const CLI = @import("cli.zig");
var mem: [4096]u8 = undefined;

// FIXME: add tests for app itself (via separate build step that runs the program
//  with different intputs), testing different i/o configurations and cli opts
pub fn main() !void {
    var fba = std.heap.FixedBufferAllocator.init(&mem);
    const alloc = fba.allocator();
    const cli = try CLI.Parse(alloc); // FIXME: handle

    if (cli.bShowHelp) {
        var stdo = std.io.getStdOut();
        _ = try stdo.write("x86fmt help\n\n\tHelp text not written yet, sorry...\n\n");
        return;
    }

    const fi, var br = reader: {
        const file = switch (cli.IKind) {
            .File => try std.fs.cwd().openFile(cli.IFile, .{}),
            .Console => std.io.getStdIn(),
        };
        const stdi_br = std.io.bufferedReader(file.reader());
        break :reader .{ file, stdi_br };
    };

    const fo, var bw = writer: {
        const file = switch (cli.OKind) {
            .File => try std.fs.cwd().createFile(cli.OFile, .{}),
            .Console => std.io.getStdOut(),
        };
        const bw = std.io.bufferedWriter(file.writer());
        break :writer .{ file, bw };
    };

    try Format(br.reader(), bw.writer(), .{}); // FIXME: handle

    bw.flush() catch unreachable; // FIXME: handle
    fo.close();
    fi.close();

    if (cli.bIOFileSame) {
        try std.fs.cwd().deleteFile(cli.IFile);
        try std.fs.cwd().rename(cli.OFile, cli.IFile);
    }
}

// TODO: comptime or runtime config
const BUF_SIZE_LINE_IO = 4096;
const BUF_SIZE_LINE_TOK = 1024;
const BUF_SIZE_LINE_LEX = 1024;
const BUF_SIZE_TOK = 256;
const MAX_CONSECUTIVE_BLANK_LINES = 2;

// TODO: ring buffer, to support line lookback
var OutBufLine = std.mem.zeroes([BUF_SIZE_LINE_IO]u8);
var ScrBufLine = std.mem.zeroes([BUF_SIZE_LINE_IO]u8);
var TokBufLine = std.mem.zeroes([BUF_SIZE_LINE_TOK]Token);
var LexBufLine = std.mem.zeroes([BUF_SIZE_LINE_LEX]Lexeme);

const TokenKind = enum(u8) { None, String, MathOp, Scope, Comma, Backslash, Whitespace };

const Token = struct {
    kind: TokenKind = .None,
    data: []const u8 = &[_]u8{},
};

const LexemeKind = enum(u8) { None, Word, Separator };

const Lexeme = struct {
    kind: LexemeKind = .None,
    data: []const Token,
};

const LexemeOpts = packed struct(u32) {
    bToLower: bool = false,
    bHeadToLower: bool = false,
    _: u30 = 0,
};

// NOTE: assembler directives: 'primitive' directives enclosed in square brackets,
//  'user-level' directives are bare
// NOTE: see chapter 8 (p.101)
/// identifiers that can appear as first word on a directive line, including aliases
const AssemblerDirective = enum { bits, use16, use32, default, section, segment, absolute, @"extern", required, global, common, static, prefix, gprefix, lprefix, suffix, gsuffix, lsuffix, cpu, dollarhex, float, warning, list };

const LineState = enum { Label, Instruction, Operands, Comment };

const LineMode = enum { Blank, Unknown, Comment, Source, Macro, AsmDirective, PreProcDirective };

const FormatError = error{SourceContainsBOM};

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
    var line_lex = std.ArrayListUnmanaged(Lexeme).initBuffer(&LexBufLine);
    var blank_lines: usize = 0;

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
        defer {
            line.clearRetainingCapacity();
            line_tok.clearRetainingCapacity();
            line_lex.clearRetainingCapacity();
        }

        if (line_i == 0 and std.mem.startsWith(u8, line_s, &[3]u8{ 0xEF, 0xBB, 0xBF }))
            return error.SourceContainsBOM;

        if (!std.unicode.utf8ValidateSlice(line_s)) {
            _ = out.write(line_s) catch unreachable; // FIXME: handle
            _ = out.write("\n") catch unreachable; // FIXME: handle
            continue;
        }

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
                        if (BLAND(scope != null, !escaped))
                            will_escape = true;
                    },
                    '\"', '\'', '`' => {
                        if (scope) |s| {
                            if (BLAND(s == c, !escaped))
                                scope = null;
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

        // the irony of nested conditional branches immediately after branchless and
        blank_lines = (blank_lines + 1) * IBLAND(body.len == 0, comment.len == 0);
        if (blank_lines > 0) {
            if (blank_lines <= MAX_CONSECUTIVE_BLANK_LINES)
                _ = out.write(if (b_crlf) "\r\n" else "\n") catch unreachable; // FIXME: handle
            continue;
        }

        var tokgen_it = std.unicode.Utf8Iterator{ .bytes = body, .i = 0 };
        tokgen: while (true) {
            const start_i = tokgen_it.i;
            const c = tokgen_it.nextCodepoint() orelse break :tokgen;
            var token: *Token = line_tok.addOneAssumeCapacity();
            switch (c) {
                ',' => {
                    token.kind = .Comma;
                    token.data = body[start_i..tokgen_it.i];
                },
                '\\' => {
                    token.kind = .Backslash;
                    token.data = body[start_i..tokgen_it.i];
                },
                '+', '-', '*', '/' => {
                    token.kind = .MathOp;
                    token.data = body[start_i..tokgen_it.i];
                },
                '(', '[', '{', ')', ']', '}', '\"', '\'', '`' => {
                    token.kind = .Scope;
                    token.data = body[start_i..tokgen_it.i];
                },
                ' ', '\t' => {
                    // skip whitespace, will be reinserted based on context
                    while (true) {
                        const peek_s = tokgen_it.peek(1);
                        const peek_chars = " \t";
                        if (BLOR(
                            peek_s.len == 0,
                            peek_s.len == 1 and std.mem.indexOfScalar(u8, peek_chars, peek_s[0]) == null,
                        )) break;

                        _ = tokgen_it.nextCodepoint();
                    }
                    _ = line_tok.pop();
                },
                else => {
                    token.kind = .String;
                    while (true) {
                        const peek_s = tokgen_it.peek(1);
                        const peek_chars = ", \t([{}])\"'`\\";
                        if (BLOR(
                            peek_s.len == 0,
                            (peek_s.len == 1 and std.mem.indexOfScalar(u8, peek_chars, peek_s[0]) != null),
                        )) break;

                        _ = tokgen_it.nextCodepoint();
                    }
                    token.data = body[start_i..tokgen_it.i];
                },
            }
        }

        // keep the stream flat since this is just for visual grouping, but this
        //  is getting dangerously close to just generating an AST lol
        // tokens -> lexeme
        {
            const scope_opener = "([{\"'`";
            const scope_closer = ")]}\"'`";
            const scope_escapable = [_]bool{ false, false, false, true, true, true };
            var scope: ?u8 = null;
            var prev_token_kind: TokenKind = .None;
            var start_i: usize = 0;
            for (line_tok.items, 0..) |t, i| {
                var emit_lexeme: ?LexemeKind = null;
                defer prev_token_kind = t.kind;
                defer if (emit_lexeme) |k| {
                    var lexeme: *Lexeme = line_lex.addOneAssumeCapacity();
                    lexeme.kind = k;
                    lexeme.data = line_tok.items[start_i .. i + 1];
                    start_i = i + 1;
                };

                switch (t.kind) {
                    .None, .Whitespace => unreachable,
                    .Scope => {
                        if (scope != null) {
                            const ci = std.mem.indexOfScalar(u8, scope_closer, t.data[0]);
                            if (ci != null and BLAND(
                                scope_opener[ci.?] == scope.?,
                                !BLAND(scope_escapable[ci.?], prev_token_kind == .Backslash),
                            )) {
                                scope = null;
                                emit_lexeme = .Word;
                            }
                            continue;
                        }
                        const oi = std.mem.indexOfScalar(u8, scope_opener, t.data[0]);
                        if (oi != null) scope = t.data[0];
                    },
                    .Comma, .Backslash, .String, .MathOp => |k| {
                        if (scope != null) continue;
                        switch (k) {
                            .Comma, .Backslash => {
                                emit_lexeme = .Separator;
                            },
                            .String, .MathOp => {
                                emit_lexeme = .Word;
                            },
                            else => unreachable,
                        }
                    },
                }
            }
        }

        const line_mode: LineMode = mode: {
            if (line_tok.items.len == 0)
                break :mode .Blank;

            const first = &line_tok.items[0];
            var case_buf: [64]u8 = undefined;

            break :mode switch (first.kind) {
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
        };

        // FIXME: give this real logic lol
        switch (line_mode) {
            // TODO: special case formatting for 'primitive'-type assembly directives
            .AsmDirective, .PreProcDirective, .Macro => {
                var fmtgen_i: usize = 0;
                var fmtgen_ci: usize = 0;
                LexAppendOpts(&line, &line_lex.items[0], &fmtgen_i, &fmtgen_ci, .{ .bHeadToLower = true });
                if (line_lex.items.len > 1) {
                    PadSpaces(&line, &fmtgen_ci, fmtgen_ci);
                    LexAppendSlice(&line, line_lex.items[1..], &fmtgen_i, &fmtgen_ci, .{});
                }
            },
            .Source => FormatSourceLine(&line, line_lex.items, &line_ctx),
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
    out: *std.ArrayListUnmanaged(u8),
    lex: []const Lexeme,
    ctx: *const LineContext,
) void {
    var b_label = false;
    var line_state: LineState = .Label;
    var fmtgen_ci: usize = 0; // utf-8 codepoints pushed
    var fmtgen_i: usize = 0;
    while (fmtgen_i < lex.len) {
        line_state = switch (line_state) {
            .Label => ls: {
                const t_len = lex[0].data[0].data.len;
                b_label = lex[0].data[0].data[t_len - 1] == ':';
                const next_s: LineState = if (b_label) st: {
                    break :st .Instruction;
                } else st: { // if not followed by ':', assume it's an instruction
                    PadSpaces(out, &fmtgen_ci, ctx.ColIns);
                    break :st .Operands;
                };

                LexAppend(out, &lex[fmtgen_i], &fmtgen_i, &fmtgen_ci);
                break :ls next_s;
            },
            .Instruction => ls: {
                PadSpaces(out, &fmtgen_ci, if (b_label) ctx.ColLabIns else ctx.ColIns);
                LexAppend(out, &lex[fmtgen_i], &fmtgen_i, &fmtgen_ci);
                break :ls .Operands;
            },
            .Operands => ls: {
                PadSpaces(out, &fmtgen_ci, if (b_label) ctx.ColLabOps else ctx.ColOps);
                LexAppendSlice(out, lex[fmtgen_i..], &fmtgen_i, &fmtgen_ci, .{});
                break :ls .Comment;
            },
            // input stream should be done by this point, comment printing will
            // be handled externally
            .Comment => unreachable,
        };
    }
}

// HELPERS

/// add spaces up to given column, adding a minimum of 1 space for padding
fn PadSpaces(line: *std.ArrayListUnmanaged(u8), col: *usize, until: usize) void {
    const n: usize = @max(1, until -| col.*);
    line.appendNTimesAssumeCapacity(32, n);
    col.* += n;
}

/// appends the contents of a lexeme to a byte array, advancing the provided
/// utf-8 codepoint counter
inline fn LexAppend(line: *std.ArrayListUnmanaged(u8), lex: *const Lexeme, i: *usize, ci: *usize) void {
    LexAppendOpts(line, lex, i, ci, .{});
}

/// appends the contents of a lexeme to a byte array, advancing the provided
/// utf-8 codepoint counter
fn LexAppendOpts(line: *std.ArrayListUnmanaged(u8), lex: *const Lexeme, i: *usize, ci: *usize, opts: LexemeOpts) void {
    switch (lex.kind) {
        .None => unreachable,
        .Separator => {
            assert(lex.data.len == 1);
            line.appendSliceAssumeCapacity(lex.data[0].data);
            line.appendAssumeCapacity(' ');
            ci.* += 1 + (std.unicode.utf8CountCodepoints(lex.data[0].data) catch unreachable);
        },
        .Word => {
            var t_kind_prev: TokenKind = .None;
            var b_lower_emitted = false;
            for (lex.data) |t| {
                defer t_kind_prev = t.kind;

                if (BLAND(t.kind == .String, t.kind == t_kind_prev))
                    line.appendAssumeCapacity(' ');

                if (BLAND(t.kind == .String, BLOR(opts.bToLower, BLAND(opts.bHeadToLower, !b_lower_emitted)))) {
                    var buf: [BUF_SIZE_TOK]u8 = undefined;
                    const lower = std.ascii.lowerString(&buf, t.data);
                    line.appendSliceAssumeCapacity(lower);
                    b_lower_emitted = true;
                } else {
                    line.appendSliceAssumeCapacity(t.data);
                }
                ci.* += std.unicode.utf8CountCodepoints(t.data) catch unreachable;
            }
        },
    }
    i.* += 1;
}

/// appends a series of lexemes to a byte array, advancing the provided utf-8
/// codepoint counter
fn LexAppendSlice(
    line: *std.ArrayListUnmanaged(u8),
    lexemes: []const Lexeme,
    i: *usize,
    ci: *usize,
    opts: LexemeOpts,
) void {
    var prev_kind: LexemeKind = .None;
    for (lexemes, 0..) |*lex, li| {
        if (BLAND(li > 0, BLAND(lex.kind != .Separator, prev_kind != .Separator)))
            PadSpaces(line, ci, i.*);
        LexAppendOpts(line, lex, i, ci, opts);
        prev_kind = lex.kind;
    }
}

// UTIL

// TODO: confirm these actually make a difference vs natural codegen

/// branchless and -> integer
inline fn IBLAND(b1: bool, b2: bool) usize {
    return @intFromBool(b1) & @intFromBool(b2);
}

/// branchless and
inline fn BLAND(b1: bool, b2: bool) bool {
    return IBLAND(b1, b2) > 0;
}

/// branchless or -> integer
inline fn IBLOR(b1: bool, b2: bool) usize {
    return @intFromBool(b1) | @intFromBool(b2);
}

/// branchless or
inline fn BLOR(b1: bool, b2: bool) bool {
    return IBLOR(b1, b2) > 0;
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
        .{ // bracketed scope
            .in = " \t  mov  dword[eax + ebp*2],16; comment",
            .ex = "    mov     dword [eax+ebp*2], 16       ; comment\n",
        },
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
        .{ // 3 blank lines -> fold to 2
            .in = "  my_label:\n\n\n\nmov eax,16; comment",
            .ex = "my_label:\n\n\n    mov     eax, 16                     ; comment\n",
        },
        .{ // 3 blank lines with comment -> not folded
            .in =
            \\my_label:
            \\
            \\; comment1
            \\
            \\mov eax,16; comment2
            ,
            // FIXME: comment1 will be in wrong position after more advanced
            //  comment formatting is implemented
            .ex =
            \\my_label:
            \\
            \\                                        ; comment1
            \\
            \\    mov     eax, 16                     ; comment2
            \\
            ,
        },
        .{ // extern (assembler directive)
            .in = "extern _SomeFunctionName@12",
            .ex = "extern _SomeFunctionName@12\n",
        },
        .{ // primitive assembler directive
            .in = " [ section  .text ] ",
            .ex = "[section .text]\n",
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
        .{ // misc preprocessor directive
            .in = "%pragma    something",
            .ex = "%pragma something\n",
        },
        .{ // comment detection
            .in = "string  db \"Atta'c'h;Console Failed!\",0; comment",
            .ex = "    string  db \"Atta'c'h;Console Failed!\", 0 ; comment\n",
        },
        .{ // invalid utf8 (codepoint malformed)
            // https://stackoverflow.com/a/3886015
            .in = "%pragma invalid_utf8_\xf0\x28\x8c\xbc",
            .ex = "%pragma invalid_utf8_\xf0\x28\x8c\xbc\n",
        },
        .{ // invalid utf8 (codepoint out of range)
            // https://stackoverflow.com/a/3886015
            .in = "%pragma invalid_utf8_\xf8\xa1\xa1\xa1\xa1",
            .ex = "%pragma invalid_utf8_\xf8\xa1\xa1\xa1\xa1\n",
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
