//! A Writer that helps manage writing with respect to line properties. Tracks
//! line length (UTF-8 codepoints since the previous newline), position of first
//! non-whitespace character, and provides a whitespace padding util.
const std = @import("std");
const io = std.io;
const assert = std.debug.assert;

// TODO: eradicate stuff like `writer.context.PadSpaces` from codebase

pub fn Utf8LineMeasuringWriter(comptime WriterType: type) type {
    return struct {
        const LMW = @This();

        pub const Error = WriterType.Error;
        pub const Writer = io.Writer(*LMW, Error, write);

        child_stream: WriterType,
        /// Current line length in UTF-8 codepoints
        LineLen: usize,
        /// Current line leading whitespace counter
        LineLws: usize,

        pub fn write(self: *LMW, bytes: []const u8) Error!usize {
            var amt: usize = 0;
            var line_it = std.mem.splitScalar(u8, bytes, '\n');

            const first = line_it.first();
            if (self.LineLen == self.LineLws)
                self.LineLws += std.mem.indexOfNone(u8, first, " \t") orelse first.len;
            self.LineLen += std.unicode.utf8CountCodepoints(first) catch first.len;
            amt += try self.child_stream.write(first);

            while (line_it.next()) |line| {
                self.LineLws = std.mem.indexOfNone(u8, line, " \t") orelse line.len;
                self.LineLen = std.unicode.utf8CountCodepoints(line) catch line.len;
                amt += try self.child_stream.write("\n");
                amt += try self.child_stream.write(line);
            }

            return amt;
        }

        pub fn writer(self: *LMW) Writer {
            return .{ .context = self };
        }

        /// Add spaces up to given column, adding at least a given minimum number
        /// of spaces
        /// @w      Utf8LineMeasuringWriter.Writer
        pub fn PadSpaces(self: *LMW, until: usize, min: usize) !void {
            const n: usize = @max(min, until -| self.LineLen);
            try self.writer().writeByteNTimes(' ', n);
        }
    };
}

pub fn utf8LineMeasuringWriter(child_stream: anytype) Utf8LineMeasuringWriter(@TypeOf(child_stream)) {
    return .{ .LineLen = 0, .LineLws = 0, .child_stream = child_stream };
}

test Utf8LineMeasuringWriter {
    // no newline
    var line_measuring_stream = utf8LineMeasuringWriter(std.io.null_writer);
    const stream = line_measuring_stream.writer();
    const bytes = "yay" ** 100;
    try stream.writeAll(bytes);
    try std.testing.expect(line_measuring_stream.LineLen == bytes.len);

    // newline
    try stream.writeAll("yay\n  yay");
    try std.testing.expect(line_measuring_stream.LineLen == 5);
    try std.testing.expect(line_measuring_stream.LineLws == 2);

    // leading whitespace surviving multiple writes
    try stream.writeAll("yeppers");
    try std.testing.expect(line_measuring_stream.LineLen == 12);
    try std.testing.expect(line_measuring_stream.LineLws == 2);
    try stream.writeAll("\n \t ");
    try stream.writeAll(" \t ");
    try stream.writeAll(" shirley");
    try std.testing.expect(line_measuring_stream.LineLen == 14);
    try std.testing.expect(line_measuring_stream.LineLws == 7);
}
