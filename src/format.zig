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
const IBLXOR = @import("util.zig").IBLXOR;
const BLSEL = @import("util.zig").BLSEL;
const BLSELE = @import("util.zig").BLSELE;
const PadSpaces = @import("util.zig").PadSpaces;
const utf8LineMeasuringWriter = @import("util.zig").utf8LineMeasuringWriter;

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
        pub const Error = error{SourceContainsBOM};

        // TODO: ring buffer, to support line lookback
        var RawBufLine = std.mem.zeroes([BUF_SIZE_LINE_IO]u8);
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
        ) !void {
            var line_tok = std.ArrayListUnmanaged(Token).initBuffer(&TokBufLine);
            var line_lex = std.ArrayListUnmanaged(Lexeme).initBuffer(&LexBufLine);
            var line_stream = utf8LineMeasuringWriter(out);
            const line = line_stream.writer();

            var line_ctx = std.mem.zeroes(Line.Context);
            line_ctx.Mode = .Blank;
            line_ctx.Section = .None;
            Line.CtxUpdateColumns(&line_ctx, &settings);

            var blank_lines: usize = 0;
            var line_i: usize = 0;
            while (in.readUntilDelimiterOrEof(&RawBufLine, '\n') catch null) |line_s| : (line_i += 1) {
                defer {
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

                const body: []const u8, const comment: []const u8 = comgen: {
                    var body_s = line_s[0..];
                    var com_s = line_s[line_s.len..];

                    const b_crlf = std.mem.endsWith(u8, body_s, "\r");
                    if (b_crlf)
                        body_s = body_s[0 .. body_s.len - 1];
                    if (line_ctx.NewLineStr.len == 0)
                        line_ctx.NewLineStr = "\r\n"[IBLXOR(true, b_crlf)..];

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

                    break :comgen .{ std.mem.trim(u8, body_s, "\t "), com_s };
                };

                // the irony of nested conditional branches immediately after branchless and
                blank_lines = (blank_lines + 1) * IBLAND(body.len == 0, comment.len == 0);
                if (blank_lines > 0) {
                    if (blank_lines <= settings.MaxBlankLines)
                        _ = out.write(line_ctx.NewLineStr) catch unreachable; // FIXME: handle
                    continue;
                }

                // TODO: smart comment positioning based on prev/next lines
                if (BLAND(body.len == 0, comment.len > 0)) {
                    _ = out.write(comment) catch unreachable; // FIXME: handle
                    _ = out.write(line_ctx.NewLineStr) catch unreachable; // FIXME: handle
                    continue;
                }

                Token.TokenizeUnicode(&line_tok, body, BUF_SIZE_TOK) catch break;
                Lexeme.ParseTokens(&line_lex, line_tok.items) catch break;
                Line.CtxParseMode(&line_ctx, line_lex.items, BUF_SIZE_TOK);
                Line.CtxUpdateSection(&line_ctx, line_lex.items, &settings, BUF_SIZE_TOK);

                switch (line_ctx.Mode) {
                    .AsmDirective,
                    .PreProcDirective,
                    .Macro,
                    => try FormatGenericDirectiveLine(&line, line_lex.items, &line_ctx),
                    .Source,
                    => try FormatSourceLine(&line, line_lex.items, &line_ctx),
                    else => {},
                }

                // NOTE: assumes the comment slice will contain the leading semicolon
                // FIXME: base on number of utf8 codepoints, not byte length of `line`
                if (comment.len > 0) {
                    try PadSpaces(line, line_ctx.ColCom, 1);
                    _ = try line.write(comment); // FIXME: handle
                }

                _ = try line.write(line_ctx.NewLineStr); // FIXME: handle
            }
        }

        /// takes a token list representing a "normal" nasm source line, and writes out
        /// the formatted results to a buffer
        /// @tok    tokenized source line, in the format produced by Token-related code
        /// @out    buffer must be empty for correct formatting
        fn FormatSourceLine(
            out: anytype, // Utf8LineMeasuringWriter.Writer
            lex: []const Lexeme,
            ctx: *const Line.Context,
        ) !void {
            var b_label = false;
            var line_state: Line.State = .Label;
            var fmtgen_i: usize = 0;
            while (fmtgen_i < lex.len) {
                line_state = switch (line_state) {
                    .Label => ls: {
                        const t_len = lex[0].data[0].data.len;
                        b_label = lex[0].data[0].data[t_len - 1] == ':';
                        try PadSpaces(out, BLSEL(b_label, usize, ctx.ColLab, ctx.ColIns), 0);
                        const next_s = BLSELE(b_label, Line.State, .Instruction, .Operands);

                        try Lexeme.BufAppend(out, &lex[fmtgen_i], &fmtgen_i, BUF_SIZE_TOK);
                        break :ls next_s;
                    },
                    .Instruction => ls: {
                        try PadSpaces(out, BLSEL(b_label, usize, ctx.ColLabIns, ctx.ColIns), 1);
                        try Lexeme.BufAppend(out, &lex[fmtgen_i], &fmtgen_i, BUF_SIZE_TOK);
                        break :ls .Operands;
                    },
                    .Operands => ls: {
                        try PadSpaces(out, BLSEL(b_label, usize, ctx.ColLabOps, ctx.ColOps), 1);
                        try Lexeme.BufAppendSlice(out, lex[fmtgen_i..], &fmtgen_i, .{}, BUF_SIZE_TOK);
                        break :ls .Comment;
                    },
                    // input stream should be done by this point, comment printing will
                    // be handled externally
                    .Comment => unreachable,
                };
            }
        }

        fn FormatGenericDirectiveLine(
            out: anytype, // Utf8LineMeasuringWriter.Writer
            lex: []const Lexeme,
            ctx: *const Line.Context,
        ) !void {
            var fmtgen_i: usize = 0;
            try PadSpaces(out, ctx.ColLab, 0);
            try Lexeme.BufAppendOpts(out, &lex[0], &fmtgen_i, .{ .bHeadToLower = true }, BUF_SIZE_TOK);
            if (lex.len > 1) {
                try out.writeByte(' ');
                try Lexeme.BufAppendSlice(out, lex[1..], &fmtgen_i, .{}, BUF_SIZE_TOK);
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
    const BUF_SIZE_LINE_IO = 4095;
    const BUF_SIZE_LINE_TOK = 1024;
    const BUF_SIZE_LINE_LEX = 512;
    const BUF_SIZE_TOK = 256;

    const fmt = Formatter(BUF_SIZE_LINE_IO, BUF_SIZE_LINE_TOK, BUF_SIZE_LINE_LEX, BUF_SIZE_TOK);

    const FormatTestCase = struct {
        in: []const u8,
        ex: []const u8 = &[_]u8{},
        err: ?fmt.Error = null,
    };

    const dummy32 = "Lorem ipsum dolor sit amet, cons";
    const dummy1 = "a";
    const test_cases = [_]FormatTestCase{
        .{ // BOM
            .in = &[_]u8{ 0xEF, 0xBB, 0xBF } ++ " \t  my_label: mov eax,16; comment",
            .err = fmt.Error.SourceContainsBOM,
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
        .{ // label and colon without whitespace
            .in = "my_label:mov eax,16",
            .ex = "my_label:   mov     eax, 16\n",
        },
        .{ // multiline with crlf break
            .in = "my_label:\r\nmov eax,16; comment",
            .ex = "my_label:\r\n    mov     eax, 16                     ; comment\r\n",
        },
        .{ // double multiline
            .in = "  my_label:\n\nmov eax,16; comment",
            .ex = "my_label:\n\n    mov     eax, 16                     ; comment\n",
        },
        .{ // double multiline crlf
            .in = "  my_label:\r\n\r\nmov eax,16; comment",
            .ex = "my_label:\r\n\r\n    mov     eax, 16                     ; comment\r\n",
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
            .ex =
            \\my_label:
            \\
            \\; comment1
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
        .{ // line length input buffer overrun (>4095)
            .in = "mov eax, 16\nmov ebp, 16 ; " ++ dummy32 ** 128,
            .ex = "    mov     eax, 16\n",
        },
        // FIXME: one character short?
        .{ // long (max) line length (4095)
            .in = "mov eax, 16\nmov ebp, 16 ; " ++ dummy32 ** 127 ++ dummy1 ** 16,
            .ex = "    mov     eax, 16\n    mov     ebp, 16                     ; " ++ dummy32 ** 127 ++ dummy1 ** 16 ++ "\n",
        },
        // FIXME: really need to move these tests to the appropriate place; starting
        // to clash a little
        // line token buffer limits (1024)
        .{ // line length token buffer overrun
            .in = "mov eax, 16\nmov ebp, 16" ++ " [es:eax]" ** 256,
            .ex = "    mov     eax, 16\n",
        },
        .{ // long (max) line tokens
            .in = "mov eax, 16\nmov ebp, 16" ++ " [es:eax]" ** 255,
            .ex = "    mov     eax, 16\n    mov     ebp, 16" ++ " [es: eax]" ** 255 ++ "\n",
        },
        // line lexeme buffer limits (512)
        .{ // line length lexeme buffer overrun
            .in = "mov eax, 16\nmov ebp, 16" ++ " a" ** 509,
            .ex = "    mov     eax, 16\n",
        },
        .{ // long (max) line lexemes
            .in = "mov eax, 16\nmov ebp, 16" ++ " a" ** 508,
            .ex = "    mov     eax, 16\n    mov     ebp, 16" ++ " a" ** 508 ++ "\n",
        },
        // individual token size limits (256)
        .{ // token size overrun
            .in = "mov " ++ "A" ** 257,
            .ex = "",
        },
        .{ // long token
            .in = "mov " ++ "A" ** 256,
            .ex = "    mov     " ++ "A" ** 256 ++ "\n",
        },
    };

    std.testing.log_level = .debug;
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
