const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var stdi = std.io.getStdIn();
    const stdi_br = std.io.bufferedReader(stdi.reader());
    var stdo = std.io.getStdOut();
    const stdo_bw = std.io.bufferedWriter(stdo.writer());
    defer stdo_bw.flush();

    try Format(alloc, stdi_br.reader(), stdo_bw.writer(), .{});
}

const FormatError = error{SourceContainsBOM};
const LineState = enum { Label, Instruction, Operands, Comment };

// TODO: option to enforce ascii? (error if codepoint above 127)
// TODO: option to force label to have its own line?
// TODO: ScratchSize may not be necessary, if the buffer is provided directly
//  i.e. derive from buffer.len
// TODO: maybe relax ScratchSize and simply not read the whole source at once; the
//  original idea was to use it to dump the original input in the case of a syntax
//  error, but maybe it's not so bad an idea to just process as many lines as
//  possible and leave the bad ones untouched. in this case, the buffer would only
//  need to be big enough for a few lines, to support multi-line features (e.g.
//  lookback to get col of prior comment for alignment), but maybe even those
//  features don't need more than one line at a time?
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
    /// Max size of buffer used to hold entire source file.
    ScratchSize: usize = 1024 * 1024 * 2, // 2 MiB
};

// NOTE: logic based on chapter 3, 5 and 8 of the NASM documentation, with some
//  compromises for the sake of practicality
// NOTE: NASM accepts only non-extended ASCII or UTF-8 without BOM; in other
//  words, it only accepts plain UTF-8
// TODO: decide whether or not an allocator is actually appropriate to provide
//  the scratch buffer
/// @alloc  used to allocate scratch buffer
/// @i      Reader to NASM source code, in a UTF-8 compatible byte stream
/// @o      Writer to the formatted code's destination byte stream
pub fn Format(
    alloc: Allocator,
    in: anytype,
    out: anytype,
    settings: FormatSettings,
) FormatError!void {
    var scratch = std.ArrayList(u8).init(alloc);
    defer scratch.deinit();

    in.readAllArrayList(&scratch, settings.ScratchSize) catch unreachable; // FIXME: handle

    if (std.mem.eql(u8, scratch.items[0..3], &[3]u8{ 0xEF, 0xBB, 0xBF })) {
        return error.SourceContainsBOM;
    }

    // NOTE: CRLF = \r\n = 13, 10
    var utf8it = std.unicode.Utf8Iterator{ .bytes = scratch.items, .i = 0 };
    var line_state: LineState = .Label;
    var token_buf: [1024]u21 = undefined;
    var tokens = std.ArrayListUnmanaged(u21).initBuffer(&token_buf);
    var line_buf: [1024]u21 = undefined;
    var line = std.ArrayListUnmanaged(u21).initBuffer(&line_buf);
    var seg_start: usize = 0;
    while (utf8it.nextCodepoint()) |codepoint| {
        line_state = switch (line_state) {
            .Label => ls: {
                const c = SkipLeadingWhitespace(&tokens, &utf8it, codepoint);

                // FIXME: handle linebreak
                // transition if needed
                if (c == 58) { // ':'
                    tokens.appendAssumeCapacity(c);
                    line.appendSliceAssumeCapacity(tokens.items);
                    PadSpaces(&line, seg_start + settings.InsMinGap);
                    break :ls EndLinePart(&line, &tokens, &seg_start, .Instruction);
                }
                if (c == 59) { // ';'
                    PadSpaces(&line, seg_start + settings.TabSize);
                    line.appendSliceAssumeCapacity(tokens.items);
                    PadSpaces(&line, settings.ComCol);
                    line.appendAssumeCapacity(c);
                    break :ls EndLinePart(&line, &tokens, &seg_start, .Comment);
                }
                if (IsWhitespace(c)) { // assume it was an Instruction if not followed by ':'
                    PadSpaces(&line, seg_start + settings.TabSize);
                    line.appendSliceAssumeCapacity(tokens.items);
                    PadSpaces(&line, seg_start + settings.TabSize + settings.OpsMinGap);
                    break :ls EndLinePart(&line, &tokens, &seg_start, .Operands);
                }

                // otherwise, keep going
                tokens.appendAssumeCapacity(c);
                break :ls line_state;
            },
            .Instruction => ls: {
                const c = SkipLeadingWhitespace(&tokens, &utf8it, codepoint);

                // FIXME: handle linebreak
                // transition if needed
                if (c == 59) { // ';'
                    line.appendSliceAssumeCapacity(tokens.items);
                    PadSpaces(&line, settings.ComCol);
                    line.appendAssumeCapacity(c);
                    break :ls EndLinePart(&line, &tokens, &seg_start, .Comment);
                }
                if (IsWhitespace(c)) {
                    line.appendSliceAssumeCapacity(tokens.items);
                    PadSpaces(&line, seg_start + settings.OpsMinGap);
                    break :ls EndLinePart(&line, &tokens, &seg_start, .Operands);
                }

                // otherwise, keep going
                tokens.appendAssumeCapacity(c);
                break :ls line_state;
            },
            .Operands => ls: {
                var c = SkipLeadingWhitespace(&tokens, &utf8it, codepoint);
                var queue_space: bool = false;

                // FIXME: handle linebreak
                // transition if needed
                if (IsWhitespace(c)) {
                    line.appendSliceAssumeCapacity(tokens.items);
                    tokens.clearRetainingCapacity();
                    queue_space = true;
                    c = SkipWhitespace(&utf8it);
                }
                if (c == 44) { // ','
                    line.appendSliceAssumeCapacity(tokens.items);
                    line.appendAssumeCapacity(c);
                    tokens.clearRetainingCapacity();
                    queue_space = true;
                    c = SkipWhitespace(&utf8it);
                }
                if (c == 59) { // ';'
                    line.appendSliceAssumeCapacity(tokens.items);
                    PadSpaces(&line, settings.ComCol);
                    line.appendAssumeCapacity(c);
                    break :ls EndLinePart(&line, &tokens, &seg_start, .Comment);
                }

                // otherwise, keep going
                if (queue_space) line.appendAssumeCapacity(32);
                tokens.appendAssumeCapacity(c);
                break :ls line_state;
            },
            .Comment => ls: {
                tokens.appendAssumeCapacity(codepoint);
                break :ls line_state;
            },
        };
    }
    line.appendSliceAssumeCapacity(tokens.items);
    tokens.clearRetainingCapacity();

    var enc_buf: [4]u8 = undefined;
    for (line.items) |c| {
        const enc_len = std.unicode.utf8Encode(c, &enc_buf) catch unreachable; // FIXME: handle
        _ = out.write(enc_buf[0..enc_len]) catch unreachable; // FIXME: handle
    }
}

fn IsWhitespace(c: u21) bool {
    return c == 32 or c == 9;
}

fn SkipWhitespace(utf8it: *std.unicode.Utf8Iterator) u21 {
    while (utf8it.nextCodepoint()) |next_c| {
        if (IsWhitespace(next_c)) continue;
        return next_c;
    }

    return 0; // FIXME: better return value?
}

fn SkipLeadingWhitespace(tokens: *std.ArrayListUnmanaged(u21), utf8it: *std.unicode.Utf8Iterator, c: u21) u21 {
    if (tokens.items.len > 0 or !IsWhitespace(c)) return c;
    return SkipWhitespace(utf8it);
}

fn PadSpaces(line: *std.ArrayListUnmanaged(u21), until: usize) void {
    line.appendNTimesAssumeCapacity(32, @max(1, until -| line.items.len));
}

fn EndLinePart(
    line: *std.ArrayListUnmanaged(u21),
    tokens: *std.ArrayListUnmanaged(u21),
    next_pos: *usize,
    next_state: LineState,
) LineState {
    tokens.clearRetainingCapacity();
    next_pos.* = line.items.len;
    return next_state;
}

// TODO: test for properly erroring at BOM
test "initial test to get things going plis rework/rename this later or else bro" {
    std.testing.log_level = .debug;
    //std.log.debug("", .{});
    //std.debug.print(" \n", .{});

    const alloc = std.testing.allocator;

    // simple standard line with all elements
    // TabSize:4  InsMinGap:12  ComCol:40
    const data_i = " \t  my_label: mov eax,16; comment";
    const data_e = "my_label:   mov     eax, 16             ; comment";

    var input = std.io.fixedBufferStream(data_i);
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    try Format(alloc, input.reader(), output.writer(), .{});

    try std.testing.expectEqualStrings(data_e, output.items);
}
