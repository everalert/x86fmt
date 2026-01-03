const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const CLI = @import("utl_cli.zig");
const Token = @import("fmt_token.zig");
const Lexeme = @import("fmt_lexeme.zig");
const Line = @import("fmt_line.zig");
const Settings = @import("fmt_settings.zig");

const BLAND = @import("utl_branchless.zig").BLAND;
const IBLAND = @import("utl_branchless.zig").IBLAND;
const BLOR = @import("utl_branchless.zig").BLOR;
const BLSEL = @import("utl_branchless.zig").BLSEL;
const BLSELE = @import("utl_branchless.zig").BLSELE;
const utf8LineMeasuringWriter = @import("utl_utf8_line_measuring_writer.zig").utf8LineMeasuringWriter;

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

        // TODO: make line ctx as input? that way, we could return an error and
        //  the caller can decide if/how to print the error wrt line information,
        //  rather than baking the error printing into this function
        /// Generic formatter for NASM-like assembly. Reader must contain valid
        /// UTF-8 without BOM; lines with invalid UTF-8 codepoints will be piped
        /// out unformatted, input with BOM will be rejected entirely.
        pub fn Format(
            reader: anytype,
            writer: anytype,
            err_writer: anytype,
            settings: Settings,
        ) !void {
            var line_s = reader.readUntilDelimiterOrEof(&RawBufLine, '\n') catch null orelse return;
            var line_i: usize = 0;

            // TODO: dump file verbatim and post message to err_writer instead?
            if (std.mem.startsWith(u8, line_s, &ByteOrderMark))
                return error.SourceContainsBOM;

            var line_tok = std.ArrayListUnmanaged(Token).initBuffer(&TokBufLine);
            var line_lex = std.ArrayListUnmanaged(Lexeme).initBuffer(&LexBufLine);
            var out = utf8LineMeasuringWriter(writer);
            const out_w = out.writer();

            var line_ctx: Line.Context = .default;
            Line.CtxUpdateColumns(&line_ctx, &settings);
            line_ctx.NewLineStr = "\r\n"[@intFromBool(!std.mem.endsWith(u8, line_s, "\r"))..];

            // TODO: line counter for output lines, use with WriteErrorMessage
            var line_ctx_prev = line_ctx;
            var blank_lines: usize = 0;
            while (true) : ({
                line_s = reader.readUntilDelimiterOrEof(&RawBufLine, '\n') catch null orelse break;
                line_i += 1;
                line_ctx_prev = line_ctx;
                line_ctx.ActualColFirst = 0;
                line_ctx.ActualColCom = 0;
                line_tok.clearRetainingCapacity();
                line_lex.clearRetainingCapacity();
            }) {
                if (!std.unicode.utf8ValidateSlice(line_s)) {
                    _ = out_w.write(line_s) catch break;
                    _ = out_w.write("\n") catch break;
                    WriteErrorMessage(err_writer, line_i, "Line Error", "InvalidUtf8") catch break;
                    continue;
                }

                const body: []const u8, const comment: []const u8 = comgen: {
                    var body_s = line_s[0..];
                    var com_s = line_s[line_s.len..];

                    const b_crlf = body_s.len > 0 and body_s[body_s.len - 1] == '\r';
                    body_s = body_s[0 .. body_s.len - @intFromBool(b_crlf)];

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
                    out.PadSpaces(colcom, 0) catch break;
                    line_ctx.ActualColCom = out.LineLen;
                    _ = out_w.write(comment) catch break;
                    _ = out_w.write(line_ctx.NewLineStr) catch break;
                    continue;
                }

                Token.TokenizeUnicode(&line_tok, body, BUF_SIZE_TOK) catch |err| {
                    WriteErrorMessage(err_writer, line_i, "Token Error", @errorName(err)) catch break;
                    _ = out_w.write(line_s) catch break;
                    _ = out_w.write("\n") catch break;
                    continue;
                };

                Lexeme.ParseTokens(&line_lex, line_tok.items) catch |err| {
                    WriteErrorMessage(err_writer, line_i, "Lexeme Error", @errorName(err)) catch break;
                    _ = out_w.write(line_s) catch break;
                    _ = out_w.write("\n") catch break;
                    continue;
                };

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
                    out.PadSpaces(line_ctx.ColCom, 1) catch break;
                    line_ctx.ActualColCom = out.LineLen;
                    _ = out_w.write(comment) catch break;
                }

                line_ctx.ActualColFirst = out.LineLws;
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
                        try writer.context.PadSpaces(BLSEL(b_label, usize, ctx.ColLab, ctx.ColIns), 0);
                        const next_s = BLSELE(b_label, Line.State, .Instruction, .Operands);

                        try Lexeme.BufAppend(writer, &lex[fmtgen_i], &fmtgen_i, BUF_SIZE_TOK);
                        break :ls next_s;
                    },
                    .Instruction => ls: {
                        try writer.context.PadSpaces(BLSEL(b_label, usize, ctx.ColLabIns, ctx.ColIns), 1);
                        try Lexeme.BufAppend(writer, &lex[fmtgen_i], &fmtgen_i, BUF_SIZE_TOK);
                        break :ls .Operands;
                    },
                    .Operands => ls: {
                        try writer.context.PadSpaces(BLSEL(b_label, usize, ctx.ColLabOps, ctx.ColOps), 1);
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
            try writer.context.PadSpaces(ctx.ColLab, 0);
            try Lexeme.BufAppendOpts(writer, &lex[0], &fmtgen_i, .{ .bHeadToLower = true }, BUF_SIZE_TOK);
            if (lex.len > 1) {
                try writer.writeByte(' ');
                try Lexeme.BufAppendSlice(writer, lex[1..], &fmtgen_i, .{}, BUF_SIZE_TOK);
            }
        }

        /// @line   zero-indexed line number
        fn WriteErrorMessage(writer: anytype, line: usize, label: []const u8, error_message: []const u8) !void {
            try writer.print("L{d:0>4}: {s} ({s})\n", .{ line + 1, label, error_message });
        }
    };
}

// TESTING

// NOTE: see annodue x86 util for testing setup reference
// TODO: FormatSettings as input in FormatTestCase
// TODO: probably migrate most of this to individual line component tests in
//  future, although some are more generic (e.g. BOM test); also real end-to-end
//  test should pull in source files at comptime?
// TODO: stderr tests (either here or in app main, probably here tho)
test "Format" {
    std.testing.log_level = .debug;
    const stde_w = std.io.null_writer;

    const BUF_SIZE_LINE_IO = 4096; // NOTE: meant to be 4095; std bug in Reader.readUntilDelimiterOrEof
    const BUF_SIZE_LINE_TOK = 1024;
    const BUF_SIZE_LINE_LEX = 512;
    const BUF_SIZE_TOK = 256;

    const fmt = Formatter(BUF_SIZE_LINE_IO, BUF_SIZE_LINE_TOK, BUF_SIZE_LINE_LEX, BUF_SIZE_TOK);

    const FormatTestCase = struct {
        in: []const u8,
        ex: []const u8 = &.{},
        err: ?fmt.Error = null,
    };

    // TODO: check that all aspects relevant to end-to-end testing covered in format.zig
    // TODO: use reference files as input. the following is semi-prepared but
    //  editing not yet final:
    //  - test/fmt.base.s
    //  - test/fmt.default.s
    //  - test/fmt.all.s
    //----
    // TODO: auto-completing scopes at end of line when scope ender not present
    //--
    //  "unclosed string  ->  "unclosed string"
    //  (unclosed paren   ->  (unclosed paren)
    //----
    // TODO: complex nested alignment
    //--
    //    \\section .data
    //    \\    FontTitle:
    //    \\    istruc ScreenFont
    //    \\        at ScreenFont.GlyphW,       db 7
    //    \\        at ScreenFont.GlyphH,       db 12
    //    \\        at ScreenFont.AdvanceX,     db 8
    //    \\        at ScreenFont.AdvanceY,     db 16
    //    \\        at ScreenFont.pGlyphs,      dd GlyphsTitle
    //    \\    iend
    //----
    // TODO: non-scoped math statements without separating spaces ?? the examples
    //  below would need 'equ' to be recognised by lexer as self-contained
    //--
    //    ATTACH_PARENT_PROCESS           equ -1
    //    ATTACH_PARENT_PROCESS_ADDR      equ $-ATTACH_PARENT_PROCESS
    //----
    // TODO: `%%success` should be indented here (currently lines up with `%macro`)
    //--
    //%macro WriteConsole 2
    //    jmp                             %%success
    //    ShowErrorMessage                str_err_write_console
    //    %%success:
    //%endmacro
    //----
    // TODO: comment should be indented here (currently in line with `section`)
    //--
    //section .data
    //    ; win32 constants
    //    NULL                            equ 0
    //----
    // TODO: ?? `HINSTANCE:` here currently lines up with `section` and `resd 1`
    //  becomes separated, not sure if should just force ppl to not use colon
    //  (no difference in nasm) or actually make it render nicely like below
    //--
    //section .bss
    //    HINSTANCE:                      resd 1
    //----
    // TODO: second comment currently lines up with first comment here, should
    //  line up with `cmp` (probably with some kind of "list comment" identifier)
    //--
    //    mov     ebx, [ebp+12]               ; msg
    //    ; handle messages
    //    cmp     ebx, WM_PAINT
    //----
    // TODO: fix: line start comment (post-blank alignment) unaffected by section
    //  indentation settings; should use the indentation as a default, unless
    //  aligning with following line as planned
    // TODO: fix: section directive affected by its own section indentation; should
    //  align to 0 as the section directive itself is "sectionless"
    //--
    //(prev section indent: 2)
    //; some dummy data for 'other' section context
    //        section .definitely_not_a_normal_section ('other' indent: 8)
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
            // FIXME: dump whole file raw instead of aborting?
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
                // token size overrun (line dumped verbatim)
                "mov " ++ "A" ** 257,
            .ex = "section .text\n" ++
                "    mov     " ++ "A" ** 256 ++ "\n" ++
                "mov " ++ "A" ** 257 ++ "\n",
        },
        // line token buffer limits (1024)
        .{
            // line length token buffer overrun (line dumped verbatim)
            .in = "section .text\n" ++
                "mov ebp, 16" ++ " [es:eax]" ** 256,
            .ex = "section .text\n" ++
                "mov ebp, 16" ++ " [es:eax]" ** 256 ++ "\n",
        },
        .{ // long (max) line tokens
            .in = "section .text\n" ++
                "mov ebp, 16" ++ " [es:eax]" ** 255,
            .ex = "section .text\n" ++
                "    mov     ebp, 16" ++ " [es: eax]" ** 255 ++ "\n",
        },
        // line lexeme buffer limits (512)
        .{
            // line length lexeme buffer overrun (line dumped verbatim)
            .in = "section .text\n" ++
                "mov ebp, 16" ++ " a" ** 509,
            .ex = "section .text\n" ++
                "mov ebp, 16" ++ " a" ** 509 ++ "\n",
        },
        .{ // long (max) line lexemes
            .in = "section .text\n" ++
                "mov ebp, 16" ++ " a" ** 508,
            .ex = "section .text\n" ++
                "    mov     ebp, 16" ++ " a" ** 508 ++ "\n",
        },
    };

    for (test_cases, 0..) |t, i| {
        errdefer std.debug.print("FAILED {d:0>2}\n\n", .{i});

        var input = std.io.fixedBufferStream(t.in);
        var output = std.ArrayList(u8).init(std.testing.allocator);
        defer output.deinit();

        const result = fmt.Format(input.reader(), output.writer(), stde_w, .default);

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
