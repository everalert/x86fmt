const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const CLI = @import("cli.zig");
const Token = @import("token.zig");
const Lexeme = @import("lexeme.zig");
const Line = @import("line.zig");

const BLAND = @import("util.zig").BLAND;
const IBLAND = @import("util.zig").IBLAND;
const BLOR = @import("util.zig").BLOR;
const PadSpaces = @import("util.zig").PadSpaces;

pub const Error = error{SourceContainsBOM};

pub const Settings = struct {
    TabSize: usize = 4,

    /// Maximum number of consecutive blank lines; large gaps will be folded to
    /// this number. Lines with comments do not count toward blanks.
    MaxBlankLines: usize = 2,

    /// Comment column, when line is not a standalone comment.
    ComCol: usize = 40,

    /// Columns between start of label and instruction, rounded up to next multiple
    /// of TabSize. Lines without a label will ignore this setting and inset the
    /// instruction by TabSize.
    InsMinGap: usize = 12,

    /// Columns between start of instruction and start of operands, rounded up to
    /// the next multiple of TabSize.
    OpsMinGap: usize = 8,

    /// Alternate values for ComCol, InsMinGap and OpsMinGap, used only in the
    /// data-type section context (e.g. ".data", ".bss", ".tls").
    DataComCol: usize = 64,
    DataInsMinGap: usize = 16,
    DataOpsMinGap: usize = 32,

    /// Base indentation for different section contexts (e.g. "section .data").
    /// Other offsets are added to these depending on the section type.
    SectionIndentNone: usize = 0,
    SectionIndentData: usize = 0,
    SectionIndentText: usize = 0,
    SectionIndentOther: usize = 0,
};

pub fn Formatter(
    comptime BUF_SIZE_LINE_IO: usize,
    comptime BUF_SIZE_LINE_TOK: usize,
    comptime BUF_SIZE_LINE_LEX: usize,
    comptime BUF_SIZE_TOK: usize,
) type {
    return struct {
        // TODO: ring buffer, to support line lookback
        var OutBufLine = std.mem.zeroes([BUF_SIZE_LINE_IO]u8);
        var ScrBufLine = std.mem.zeroes([BUF_SIZE_LINE_IO]u8);
        var TokBufLine = std.mem.zeroes([BUF_SIZE_LINE_TOK]Token);
        var LexBufLine = std.mem.zeroes([BUF_SIZE_LINE_LEX]Lexeme);

        // NOTE: logic based on chapter 3, 5 and 8 of the NASM documentation, with some
        //  compromises for the sake of practicality
        /// @i      Reader to NASM source code, in a UTF-8 compatible byte stream
        /// @o      Writer to the formatted code's destination byte stream
        pub fn Format(
            in: anytype,
            out: anytype,
            settings: Settings,
        ) Error!void {
            var line = std.ArrayListUnmanaged(u8).initBuffer(&OutBufLine);
            var line_tok = std.ArrayListUnmanaged(Token).initBuffer(&TokBufLine);
            var line_lex = std.ArrayListUnmanaged(Lexeme).initBuffer(&LexBufLine);

            var line_ctx = std.mem.zeroes(Line.Context);
            line_ctx.Mode = .Blank;
            line_ctx.Section = .None;
            Line.CtxUpdateColumns(&line_ctx, &settings);

            var blank_lines: usize = 0;
            var line_i: usize = 0;
            // FIXME: handle line read error
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
                    if (blank_lines <= settings.MaxBlankLines)
                        _ = out.write(if (b_crlf) "\r\n" else "\n") catch unreachable; // FIXME: handle
                    continue;
                }

                Token.TokenizeUnicode(&line_tok, body);
                Lexeme.ParseTokens(&line_lex, line_tok.items);
                Line.CtxParseMode(&line_ctx, line_lex.items, BUF_SIZE_TOK);
                Line.CtxUpdateSection(&line_ctx, line_lex.items, &settings, BUF_SIZE_TOK);

                // FIXME: give this real logic lol
                // TODO: special case formatting for 'primitive'-type assembly directives
                switch (line_ctx.Mode) {
                    .AsmDirective,
                    .PreProcDirective,
                    .Macro,
                    => FormatGenericDirectiveLine(&line, line_lex.items),
                    .Source,
                    => FormatSourceLine(&line, line_lex.items, &line_ctx),
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
                // FIXME: branchless (also at the other spot)
                _ = out.write(if (b_crlf) "\r\n" else "\n") catch unreachable; // FIXME: handle
            }
        }

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
            ctx: *const Line.Context,
        ) void {
            var b_label = false;
            var line_state: Line.State = .Label;
            var fmtgen_ci: usize = 0; // utf-8 codepoints pushed
            var fmtgen_i: usize = 0;
            while (fmtgen_i < lex.len) {
                line_state = switch (line_state) {
                    .Label => ls: {
                        const t_len = lex[0].data[0].data.len;
                        b_label = lex[0].data[0].data[t_len - 1] == ':';
                        const next_s: Line.State = if (b_label) st: {
                            break :st .Instruction;
                        } else st: { // if not followed by ':', assume it's an instruction
                            PadSpaces(out, &fmtgen_ci, ctx.ColIns);
                            break :st .Operands;
                        };

                        Lexeme.BufAppend(out, &lex[fmtgen_i], &fmtgen_i, &fmtgen_ci, BUF_SIZE_TOK);
                        break :ls next_s;
                    },
                    .Instruction => ls: {
                        PadSpaces(out, &fmtgen_ci, if (b_label) ctx.ColLabIns else ctx.ColIns);
                        Lexeme.BufAppend(out, &lex[fmtgen_i], &fmtgen_i, &fmtgen_ci, BUF_SIZE_TOK);
                        break :ls .Operands;
                    },
                    .Operands => ls: {
                        PadSpaces(out, &fmtgen_ci, if (b_label) ctx.ColLabOps else ctx.ColOps);
                        Lexeme.BufAppendSlice(out, lex[fmtgen_i..], &fmtgen_i, &fmtgen_ci, .{}, BUF_SIZE_TOK);
                        break :ls .Comment;
                    },
                    // input stream should be done by this point, comment printing will
                    // be handled externally
                    .Comment => unreachable,
                };
            }
        }

        fn FormatGenericDirectiveLine(
            out: *std.ArrayListUnmanaged(u8),
            lex: []const Lexeme,
        ) void {
            var fmtgen_i: usize = 0;
            var fmtgen_ci: usize = 0;
            Lexeme.BufAppendOpts(out, &lex[0], &fmtgen_i, &fmtgen_ci, .{ .bHeadToLower = true }, BUF_SIZE_TOK);
            if (lex.len > 1) {
                PadSpaces(out, &fmtgen_ci, fmtgen_ci);
                Lexeme.BufAppendSlice(out, lex[1..], &fmtgen_i, &fmtgen_ci, .{}, BUF_SIZE_TOK);
            }
        }
    };
}

// TESTING

// NOTE: see annodue x86 util for testing setup reference
// TODO: FormatSettings as input in FormatTestCase
// TODO: probably migrate most of this to individual line component tests in
//  future, although some are more generic (e.g. BOM test); also real end-to-end
//  test should pull in source files at comptime?
test "Format" {
    const BUF_SIZE_LINE_IO = 4096;
    const BUF_SIZE_LINE_TOK = 1024;
    const BUF_SIZE_LINE_LEX = 1024;
    const BUF_SIZE_TOK = 256;

    const FormatTestCase = struct {
        in: []const u8,
        ex: []const u8 = &[_]u8{},
        err: ?Error = null,
    };

    const test_cases = [_]FormatTestCase{
        .{ // BOM
            .in = &[_]u8{ 0xEF, 0xBB, 0xBF } ++ " \t  my_label: mov eax,16; comment",
            .err = Error.SourceContainsBOM,
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
        .{ // section text, primitive assembler directive
            .in = " [ section  .text ] ",
            .ex = "[section .text]\n",
        },
        .{ // section data
            .in =
            \\section .rodata
            \\strloc_errmsg_format_err equ 9 ; start of error code
            ,
            .ex =
            \\section .rodata
            \\    strloc_errmsg_format_err        equ 9                       ; start of error code
            \\
            ,
        },
        .{ // section other
            .in = "section  whatever",
            .ex = "section whatever\n",
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
    const fmt = Formatter(BUF_SIZE_LINE_IO, BUF_SIZE_LINE_TOK, BUF_SIZE_LINE_LEX, BUF_SIZE_TOK);
    for (test_cases, 0..) |t, i| {
        errdefer std.debug.print("FAILED {d:0>2}\n\n", .{i});

        var input = std.io.fixedBufferStream(t.in);
        var output = std.ArrayList(u8).init(std.testing.allocator);
        defer output.deinit();

        const f = fmt.Format(input.reader(), output.writer(), .{});

        if (t.err) |ex_err| {
            try std.testing.expectError(ex_err, f);
        } else {
            try std.testing.expectEqualStrings(t.ex, output.items);
            try std.testing.expectEqual(t.ex.len, output.items.len);
        }
    }
}
