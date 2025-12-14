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

// TODO: ring buffer, to support line lookback
threadlocal var ScrBufLine = std.mem.zeroes([4096]u8);
threadlocal var OutBufLine = std.mem.zeroes([4096]u21);
threadlocal var OutBufToken = std.mem.zeroes([256]u21);

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
    assert(settings.TabSize > 0);
    assert(std.math.isPowerOfTwo(settings.TabSize));

    const gap_ins: usize = (settings.InsMinGap + settings.TabSize - 1) & ~(settings.TabSize - 1);
    const gap_ops: usize = (settings.OpsMinGap + settings.TabSize - 1) & ~(settings.TabSize - 1);
    const col_com: usize = (settings.ComCol + settings.TabSize - 1) & ~(settings.TabSize - 1);
    const col_ins: usize = settings.TabSize;
    const col_ops: usize = col_ins + gap_ops;
    const col_labins: usize = gap_ins;
    const col_labops: usize = col_labins + gap_ops;

    var tokens = std.ArrayListUnmanaged(u21).initBuffer(&OutBufToken);
    var line = std.ArrayListUnmanaged(u21).initBuffer(&OutBufLine);
    var b_crlf = false;

    // FIXME: handle line read error
    var line_i: usize = 0;
    while (in.readUntilDelimiterOrEof(&ScrBufLine, '\n') catch unreachable) |line_s| : (line_i += 1) {
        if (line_i == 0 and std.mem.startsWith(u8, line_s, &[3]u8{ 0xEF, 0xBB, 0xBF }))
            return error.SourceContainsBOM;

        // TODO: just always output newline after pushing line?
        if (line_i > 0) {
            _ = out.write(if (b_crlf) "\r\n" else "\n") catch unreachable; // FIXME: handle
        }

        b_crlf = false;
        var b_label = false;
        var b_state_initialized = false;
        var line_state: LineState = .Label;

        // work slice
        const line_ws: []const u8 = ws: {
            var line_ws = line_s;
            if (std.mem.endsWith(u8, line_ws, "\r")) {
                line_ws = line_ws[0 .. line_ws.len - 1];
                b_crlf = true;
            }
            break :ws std.mem.trim(u8, line_ws, "\t ");
        };

        var utf8it = std.unicode.Utf8Iterator{ .bytes = line_ws, .i = 0 };
        while (utf8it.nextCodepoint()) |codepoint| {
            var c = codepoint;
            var next_s: LineState = .Comment;
            line_state = switch (line_state) {
                .Label => ls: {
                    c = SkipWhitespace(&utf8it, c);
                    c = ConsumeUntilCharacter(&utf8it, &tokens, c, &[_]u21{ '\t', ' ', ':', ';' });

                    if (c == ':') {
                        b_label = true;
                        next_s = .Instruction;
                        tokens.appendAssumeCapacity(c);
                    } else { // if not followed by ':', assume it's an instruction
                        if (c != ';') next_s = .Operands;
                        PadSpaces(&line, col_ins);
                    }
                    line.appendSliceAssumeCapacity(tokens.items);
                    break :ls EndLinePart(&tokens, &b_state_initialized, next_s);
                },
                .Instruction => ls: {
                    if (!b_state_initialized) {
                        b_state_initialized = true;
                        PadSpaces(&line, if (b_label) col_labins else col_ins);
                    }
                    c = SkipWhitespace(&utf8it, c);
                    c = ConsumeUntilCharacter(&utf8it, &tokens, c, &[_]u21{ '\t', ' ', ';' });

                    if (c != ';') next_s = .Operands;
                    line.appendSliceAssumeCapacity(tokens.items);
                    break :ls EndLinePart(&tokens, &b_state_initialized, next_s);
                },
                .Operands => ls: {
                    if (!b_state_initialized) {
                        b_state_initialized = true;
                        PadSpaces(&line, if (b_label) col_labops else col_ops);
                    }
                    c = SkipWhitespace(&utf8it, c);
                    c = ConsumeUntilCharacter(&utf8it, &tokens, c, &[_]u21{ '\t', ' ', ',', ';' });

                    line.appendSliceAssumeCapacity(tokens.items);
                    if (c == ',' or IsWhitespace(c)) {
                        if (c == ',') line.appendAssumeCapacity(c);
                        tokens.clearRetainingCapacity();
                        line.appendAssumeCapacity(32);
                        break :ls line_state;
                    }
                    break :ls EndLinePart(&tokens, &b_state_initialized, .Comment);
                },
                .Comment => ls: {
                    if (!b_state_initialized) {
                        b_state_initialized = true;
                        PadSpaces(&line, col_com);
                        line.appendAssumeCapacity(';');
                    }
                    tokens.appendAssumeCapacity(c);
                    break :ls line_state;
                },
            };
        }
        line.appendSliceAssumeCapacity(tokens.items);

        for (line.items) |c| {
            var enc_buf: [4]u8 = undefined;
            const enc_len = std.unicode.utf8Encode(c, &enc_buf) catch unreachable; // FIXME: handle
            _ = out.write(enc_buf[0..enc_len]) catch unreachable; // FIXME: handle
        }

        tokens.clearRetainingCapacity();
        line.clearRetainingCapacity();
    }
}

// HELPERS

fn ConsumeUntilCharacter(
    utf8it: *std.unicode.Utf8Iterator,
    tokens: *std.ArrayListUnmanaged(u21),
    this_c: u21,
    chars: []const u21,
) u21 {
    var c = this_c;
    while (std.mem.indexOf(u21, chars, @as(*[1]u21, &c)) == null) {
        tokens.appendAssumeCapacity(c);
        c = utf8it.nextCodepoint() orelse break;
    }
    return c;
}

fn IsWhitespace(c: u21) bool {
    return c == 32 or c == 9;
}

fn SkipWhitespace(utf8it: *std.unicode.Utf8Iterator, c: u21) u21 {
    if (!IsWhitespace(c)) return c;
    while (utf8it.nextCodepoint()) |next_c| {
        if (IsWhitespace(next_c)) continue;
        return next_c;
    }
    return 0; // FIXME: better return value?
}

fn PadSpaces(line: *std.ArrayListUnmanaged(u21), until: usize) void {
    line.appendNTimesAssumeCapacity(32, @max(1, until -| line.items.len));
}

fn EndLinePart(
    tokens: *std.ArrayListUnmanaged(u21),
    next_initialized: *bool,
    next_state: LineState,
) LineState {
    next_initialized.* = false;
    tokens.clearRetainingCapacity();
    return next_state;
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
            .ex = "my_label:   mov     eax, 16             ; comment",
        },
        .{ // no label
            .in = " \t  mov eax,16; comment",
            .ex = "    mov     eax, 16                     ; comment",
        },
        .{ // multiline with lone "label header"
            .in =
            \\    my_label:
            \\mov eax,16; comment
            ,
            .ex =
            \\my_label:
            \\    mov     eax, 16                     ; comment
            ,
        },
        .{ // multiline with crlf break
            .in = "  my_label:\r\nmov eax,16; comment",
            .ex = "my_label:\r\n    mov     eax, 16                     ; comment",
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
