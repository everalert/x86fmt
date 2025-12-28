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
    TextComCol: usize = 40,

    /// Columns to advance from start of label to instruction. Lines without a
    /// label will ignore this setting and inset the instruction by TabSize.
    TextInsMinAdv: usize = 12,

    /// Columns to advance from start of instruction to operands.
    TextOpsMinAdv: usize = 8,

    /// Alternate values for ComCol, InsMinGap and OpsMinGap, used only in the
    /// data-type section context (e.g. ".data", ".bss", ".tls").
    DataComCol: usize = 60,
    DataInsMinAdv: usize = 16,
    DataOpsMinAdv: usize = 32,

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
        const ByteOrderMark = [3]u8{ 0xEF, 0xBB, 0xBF };

        // TODO: ring buffer, to support line lookback
        var RawBufLine = std.mem.zeroes([BUF_SIZE_LINE_IO]u8);
        var TokBufLine = std.mem.zeroes([BUF_SIZE_LINE_TOK]Token);
        var LexBufLine = std.mem.zeroes([BUF_SIZE_LINE_LEX]Lexeme);

        /// Generic formatter for NASM-like assembly. Reader must contain valid
        /// UTF-8 without BOM; lines with invalid UTF-8 codepoints will be piped
        /// out unformatted, input with BOM will be rejected entirely.
        pub fn Format(
            reader: anytype,
            writer: anytype,
            settings: Settings,
        ) !void {
            var line_tok = std.ArrayListUnmanaged(Token).initBuffer(&TokBufLine);
            var line_lex = std.ArrayListUnmanaged(Lexeme).initBuffer(&LexBufLine);
            var out_stream = utf8LineMeasuringWriter(writer);
            const out_w = out_stream.writer();

            var line_ctx = std.mem.zeroes(Line.Context);
            line_ctx.Mode = .Blank;
            line_ctx.Section = .None;
            Line.CtxUpdateColumns(&line_ctx, &settings);

            var line_ctx_prev = line_ctx;
            var blank_lines: usize = 0;
            var line_i: usize = 0;
            while (reader.readUntilDelimiterOrEof(&RawBufLine, '\n') catch null) |line_s| : (line_i += 1) {
                defer {
                    line_ctx_prev = line_ctx;
                    line_ctx.ActualColFirst = 0;
                    line_ctx.ActualColCom = 0;
                    line_tok.clearRetainingCapacity();
                    line_lex.clearRetainingCapacity();
                }

                if (line_i == 0 and std.mem.startsWith(u8, line_s, &ByteOrderMark))
                    return error.SourceContainsBOM;

                if (!std.unicode.utf8ValidateSlice(line_s)) {
                    _ = out_w.write(line_s) catch break;
                    _ = out_w.write("\n") catch break;
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
                        _ = out_w.write(line_ctx.NewLineStr) catch break;
                    continue;
                }

                // TODO: smart comment positioning based on prev/next lines
                if (BLAND(body.len == 0, comment.len > 0)) {
                    const colcom = @max(line_ctx_prev.ActualColCom, line_ctx_prev.ActualColFirst);
                    PadSpaces(out_w, colcom, 0) catch break;
                    line_ctx.ActualColCom = out_stream.line_len;
                    _ = out_w.write(comment) catch break;
                    _ = out_w.write(line_ctx.NewLineStr) catch break;
                    continue;
                }

                Token.TokenizeUnicode(&line_tok, body, BUF_SIZE_TOK) catch break;
                Lexeme.ParseTokens(&line_lex, line_tok.items) catch break;
                Line.CtxParseMode(&line_ctx, line_lex.items);
                Line.CtxUpdateSection(&line_ctx, line_lex.items, &settings);

                switch (line_ctx.Mode) {
                    .AsmDirective,
                    .PreProcDirective,
                    .Macro,
                    => FormatGenericDirectiveLine(&out_w, line_lex.items, &line_ctx) catch break,
                    .Source,
                    => FormatSourceLine(&out_w, line_lex.items, &line_ctx) catch break,
                    else => unreachable,
                }

                // NOTE: assumes the comment slice will contain the leading semicolon
                if (comment.len > 0) {
                    PadSpaces(out_w, line_ctx.ColCom, 1) catch break;
                    line_ctx.ActualColCom = out_stream.line_len;
                    _ = out_w.write(comment) catch break;
                }

                line_ctx.ActualColFirst = out_stream.line_lws;
                _ = out_w.write(line_ctx.NewLineStr) catch break;
            }
        }

        /// takes a token list representing a "normal" nasm source line, and writes out
        /// the formatted results to a buffer
        /// @tok    tokenized source line, in the format produced by Token-related code
        /// @out    buffer must be empty for correct formatting
        fn FormatSourceLine(
            writer: anytype, // Utf8LineMeasuringWriter.Writer
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
                        try PadSpaces(writer, BLSEL(b_label, usize, ctx.ColLab, ctx.ColIns), 0);
                        const next_s = BLSELE(b_label, Line.State, .Instruction, .Operands);

                        try Lexeme.BufAppend(writer, &lex[fmtgen_i], &fmtgen_i, BUF_SIZE_TOK);
                        break :ls next_s;
                    },
                    .Instruction => ls: {
                        try PadSpaces(writer, BLSEL(b_label, usize, ctx.ColLabIns, ctx.ColIns), 1);
                        try Lexeme.BufAppend(writer, &lex[fmtgen_i], &fmtgen_i, BUF_SIZE_TOK);
                        break :ls .Operands;
                    },
                    .Operands => ls: {
                        try PadSpaces(writer, BLSEL(b_label, usize, ctx.ColLabOps, ctx.ColOps), 1);
                        try Lexeme.BufAppendSlice(writer, lex[fmtgen_i..], &fmtgen_i, .{}, BUF_SIZE_TOK);
                        break :ls .Comment;
                    },
                    // input stream should be done by this point, comment printing will
                    // be handled externally
                    .Comment => unreachable,
                };
            }
        }

        fn FormatGenericDirectiveLine(
            writer: anytype, // Utf8LineMeasuringWriter.Writer
            lex: []const Lexeme,
            ctx: *const Line.Context,
        ) !void {
            var fmtgen_i: usize = 0;
            try PadSpaces(writer, ctx.ColLab, 0);
            try Lexeme.BufAppendOpts(writer, &lex[0], &fmtgen_i, .{ .bHeadToLower = true }, BUF_SIZE_TOK);
            if (lex.len > 1) {
                try writer.writeByte(' ');
                try Lexeme.BufAppendSlice(writer, lex[1..], &fmtgen_i, .{}, BUF_SIZE_TOK);
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
    const BUF_SIZE_LINE_IO = 4096; // NOTE: meant to be 4095; std bug in Reader.readUntilDelimiterOrEof
    const BUF_SIZE_LINE_TOK = 1024;
    const BUF_SIZE_LINE_LEX = 512;
    const BUF_SIZE_TOK = 256;

    const fmt = Formatter(BUF_SIZE_LINE_IO, BUF_SIZE_LINE_TOK, BUF_SIZE_LINE_LEX, BUF_SIZE_TOK);

    const FormatTestCase = struct {
        in: []const u8,
        ex: []const u8 = &[_]u8{},
        err: ?fmt.Error = null,
    };

    // TODO: complex nested alignment
    //    \\section .data
    //    \\	FontTitle:
    //    \\	istruc ScreenFont
    //    \\		at ScreenFont.GlyphW,		db 7
    //    \\		at ScreenFont.GlyphH,		db 12
    //    \\		at ScreenFont.AdvanceX,		db 8
    //    \\		at ScreenFont.AdvanceY,		db 16
    //    \\		at ScreenFont.pGlyphs,		dd GlyphsTitle
    //    \\	iend
    // TODO: non-scoped math statements without separating spaces ?? the examples
    //  below would need 'equ' to be recognised by lexer as self-contained
    //    ATTACH_PARENT_PROCESS           equ -1
    //    ATTACH_PARENT_PROCESS_ADDR      equ $-ATTACH_PARENT_PROCESS
    //
    const dummy32 = "Lorem ipsum dolor sit amet, cons";
    const dummy1 = "a";
    const test_cases = [_]FormatTestCase{
        .{
            // consolidated test of cases which should stay the same in the event
            // that parsing is successful
            // NOTE: may need more thorough testing of switching different types
            //  of sections, some text/data labels not checked
            .in =
            // NOTE: START: default section formatting
            // -- currently should match data section
            // default section should have data section formatting, also this
            // shouldn't just fold in general
            \\    struc                           ScreenBuffer
            \\    .Width                          resd 1
            \\    .Height                         resd 1
            \\    .BytesPerPixel                  resd 1
            \\    .Pitch                          resd 1
            \\    .Memory                         resd 1
            \\    .hBitmap                        resd 1
            \\    .Info                           resb BITMAPINFOHEADER_size
            \\    endstruc
            // TODO: should be something like this instead once nested stuff is done
            //\\struc ScreenBuffer
            //\\    .Width                          resd 1
            //\\    .Height                         resd 1
            //\\    .BytesPerPixel                  resd 1
            //\\    .Pitch                          resd 1
            //\\    .Memory                         resd 1
            //\\    .hBitmap                        resd 1
            //\\    .Info                           resb BITMAPINFOHEADER_size
            //\\endstruc
            // START: text section formatting
            \\section .text
            \\
            // line with all 4
            \\my_label:   mov     eax, 16             ; comment
            \\
            // no label
            \\    mov     eax, 16                     ; comment
            \\
            // bracketed scope
            \\    mov     dword [eax+ebp*2], 16       ; comment
            \\
            // multiline with lone "label header"
            \\my_label:
            \\    mov     eax, 16                     ; comment
            \\
            // double multiline
            \\my_label:
            \\
            \\    mov     eax, 16                     ; comment
            \\
            // extern (assembler directive)
            \\extern _SomeFunctionName@12
            \\
            // NOTE: START: data section formatting
            \\section .rodata
            \\
            \\    strloc_errmsg_format_err        equ 9                   ; start of error code
            \\
            // correct comment detection in presence of string with semicolon
            \\    string_not_comment              db "no't'c;omment!", 0  ; comment
            \\
            // NOTE: START: text section formatting (correctly switching formatting back)
            // primitive assembler directive
            \\[section .text]
            \\
            // misc preprocessor directive
            \\%pragma something
            \\
            // NOTE: START: "other" section formatting (currently should match text section)
            \\section whatever
            \\
            // ensure whitespace isn't removed from nasm strings
            \\    strname db " [ERROR] (00000000) ", 0
            \\
            // extend nasm strings to end if newline hit without string scope closer
            \\    strname db " [ERROR] (00000000) , 0
            \\
            // comment-only line aligning with previous comment
            \\    sub     esp, 32                     ; 00 = x-base for pos side
            \\                                        ; 04 = y-base for pos side
            \\                                        ; 08 = x-base for neg side
            \\
            // TODO: comment-only line aligning with next line if prev line blank
            // comment-only line aligning with previous text if not blank
            \\    sub     esp, 32
            \\    ; 08 = x-base for neg side
            \\    ; 08 = x-base for neg side
            \\
            \\; 08 = x-base for neg side
            \\
            // END
            \\
            ,
        },
        // NOTE: code that either needs to be in a separate test, or otherwise
        //  needs further consideration or treatment
        // NOTE: also, generally speaking any test that requires comparing
        //  with a different output (no .ex=null) is a reason for separation
        //  within format.zig (so i don't have to keep writing this)
        // ----------------
        // BOM
        .{
            .in = &[_]u8{ 0xEF, 0xBB, 0xBF } ++ " \t  my_label: mov eax,16; comment",
            .err = fmt.Error.SourceContainsBOM,
        },
        // CRLF treatment (both ways due to ambiguity of backslash literal)
        .{
            // CRLF
            .in = "section .text\r\n" ++
                // multiline with crlf break
                "my_label:\r\n" ++
                "mov eax,16; comment\r\n" ++
                // double multiline crlf
                "my_label:\r\n" ++
                "\r\n" ++
                "mov eax,16; comment\r\n" ++
                // homogenize to crlf based on first line break
                "my_label:\n" ++
                "mov eax,16; comment",
            .ex = "section .text\r\n" ++
                "my_label:\r\n" ++
                "    mov     eax, 16                     ; comment\r\n" ++
                "my_label:\r\n" ++
                "\r\n" ++
                "    mov     eax, 16                     ; comment\r\n" ++
                "my_label:\r\n" ++
                "    mov     eax, 16                     ; comment\r\n",
        },
        .{
            // LF-only
            .in = "section .text\n" ++
                // multiline with lf-only break
                "my_label:\n" ++
                "mov eax,16; comment\n" ++
                // double multiline lf-only
                "my_label:\n" ++
                "\n" ++
                "mov eax,16; comment\n" ++
                // homogenize to lf-only based on first line break
                "my_label:\r\n" ++
                "mov eax,16; comment",
            .ex = "section .text\n" ++
                "my_label:\n" ++
                "    mov     eax, 16                     ; comment\n" ++
                "my_label:\n" ++
                "\n" ++
                "    mov     eax, 16                     ; comment\n" ++
                "my_label:\n" ++
                "    mov     eax, 16                     ; comment\n",
        },
        // blank line folding
        .{
            .in =
            \\section .text
            // 3 blank lines -> fold to 2
            \\my_label:
            \\
            \\
            \\
            \\mov eax,16; comment
            // 3 blank lines with comment -> not folded
            \\my_label:
            \\
            \\; comment1
            \\
            \\mov eax,16; comment2
            ,
            .ex =
            \\section .text
            \\my_label:
            \\
            \\
            \\    mov     eax, 16                     ; comment
            \\my_label:
            \\
            \\; comment1
            \\
            \\    mov     eax, 16                     ; comment2
            \\
            ,
        },
        // TODO: ?? add case-insensitivity tests for non-macro directives
        // TODO: ?? add tests for macro directives in non-case insensivitiy context
        // case-insensitive directive header word, preserving case for non-header
        .{
            .in =
            \\section .text
            // %macro
            \\%mACRO CoolMacro 2
            // %imacro
            \\%IMAcro CoolMacro 2
            // %endmacro
            \\%enDMACro
            ,
            .ex =
            \\section .text
            \\%macro CoolMacro 2
            \\%imacro CoolMacro 2
            \\%endmacro
            \\
        },
        // non-trivial whitespace
        .{
            // label and colon without whitespace
            .in =
            \\section .text
            \\my_label:mov eax,16
            // removing excess whitespace in scope context
            \\ [ section  .text ] a
            ,
            .ex =
            \\section .text
            \\my_label:   mov     eax, 16
            \\[section .text] a
            \\
            ,
        },
        // pass through invalid utf-8 without formatting
        // https://stackoverflow.com/a/3886015
        .{
            .in = "section .text\n" ++
                // invalid utf8 (codepoint malformed)
                "%pragma     invalid_utf8_\xf0\x28\x8c\xbc \n" ++
                // invalid utf8 (codepoint out of range)
                "%pragma   invalid_utf8_\xf8\xa1\xa1\xa1\xa1   \n",
        },
        // line byte limit (4095)
        // WARN: BUF_SIZE_LINE_IO==4096 in order to have 4095 boundary; std bug
        //  in Reader.readUntilDelimiterOrEof causes early error
        // TODO: passthrough in this context instead of aborting? also, in future
        //  this may not be relevant with a new memory/parsing model
        .{
            .in = "section .text\n" ++
                // long (max) line length
                "mov ebp, 16 ; " ++ dummy32 ** 127 ++ dummy1 ** 17 ++ "\n" ++
                // line byte limit overrun (line dropped)
                "mov ebp, 16 ; " ++ dummy32 ** 127 ++ dummy1 ** 18,
            .ex = "section .text\n" ++
                "    mov     ebp, 16                     ; " ++ dummy32 ** 127 ++ dummy1 ** 17 ++ "\n",
        },
        // individual token size limits (256)
        .{
            .in = "section .text\n" ++
                // long token
                "mov " ++ "A" ** 256 ++ "\n" ++
                // token size overrun (line dropped)
                "mov " ++ "A" ** 257,
            .ex = "section .text\n" ++
                "    mov     " ++ "A" ** 256 ++ "\n",
        },
        // FIXME: tests that specifically need to be moved to a different module
        // TODO: check that all aspects relevant to end-to-end testing covered in format.zig
        // ----------------
        // FIXME: really need to move these tests to the appropriate place; starting
        //  to clash a little
        // TODO: also simplify these tests so that there's not unrelated extra
        //  lines and such harming readability
        // TODO: that said, do need some tests to confirm the previous lines do
        //  not affect the results of following ones
        // line token buffer limits (1024)
        .{ // line length token buffer overrun
            .in = "section .text\n" ++
                "mov ebp, 16" ++ " [es:eax]" ** 256,
            .ex = "section .text\n",
        },
        .{ // long (max) line tokens
            .in = "section .text\n" ++
                "mov ebp, 16" ++ " [es:eax]" ** 255,
            .ex = "section .text\n" ++
                "    mov     ebp, 16" ++ " [es: eax]" ** 255 ++ "\n",
        },
        // line lexeme buffer limits (512)
        .{ // line length lexeme buffer overrun
            .in = "section .text\n" ++
                "mov ebp, 16" ++ " a" ** 509,
            .ex = "section .text\n",
        },
        .{ // long (max) line lexemes
            .in = "section .text\n" ++
                "mov ebp, 16" ++ " a" ** 508,
            .ex = "section .text\n" ++
                "    mov     ebp, 16" ++ " a" ** 508 ++ "\n",
        },
    };

    std.testing.log_level = .debug;
    for (test_cases, 0..) |t, i| {
        errdefer std.debug.print("FAILED {d:0>2}\n\n", .{i});

        var input = std.io.fixedBufferStream(t.in);
        var output = std.ArrayList(u8).init(std.testing.allocator);
        defer output.deinit();

        const result = fmt.Format(input.reader(), output.writer(), .{});

        if (t.err) |e| {
            try std.testing.expectError(e, result);
        } else {
            try result;
            const ex = if (t.ex.len > 0) t.ex else t.in;
            try std.testing.expectEqualStrings(ex, output.items);
            try std.testing.expectEqual(ex.len, output.items.len);
        }
    }
}
