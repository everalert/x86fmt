const std = @import("std");
const io = std.io;
const assert = std.debug.assert;

// BRANCHLESS

/// Branchless AND -> int
pub inline fn IBLAND(b1: bool, b2: bool) usize {
    return @intFromBool(b1) & @intFromBool(b2);
}

/// Branchless AND
pub inline fn BLAND(b1: bool, b2: bool) bool {
    return IBLAND(b1, b2) > 0;
}

/// Branchless OR -> int
pub inline fn IBLOR(b1: bool, b2: bool) usize {
    return @intFromBool(b1) | @intFromBool(b2);
}

/// Branchless OR
pub inline fn BLOR(b1: bool, b2: bool) bool {
    return IBLOR(b1, b2) > 0;
}

/// Branchless XOR -> int
pub inline fn IBLXOR(b1: bool, b2: bool) usize {
    return @intFromBool(b1) ^ @intFromBool(b2);
}

/// Branchless XOR
pub inline fn BLXOR(b1: bool, b2: bool) bool {
    return IBLXOR(b1, b2) > 0;
}

/// Branchless switch on bool -> int
pub inline fn BLSEL(b: bool, comptime T: type, n1: T, n2: T) T {
    comptime assert(@typeInfo(T) == .Int);
    return @intFromBool(b) * n1 + @intFromBool(!b) * n2;
}

/// Branchless switch on bool -> enum
pub inline fn BLSELE(b: bool, comptime T: type, v1: T, v2: T) T {
    comptime assert(@typeInfo(T) == .Enum);
    return @enumFromInt(@intFromBool(b) * @intFromEnum(v1) + @intFromBool(!b) * @intFromEnum(v2));
}

// PADDING

/// Add spaces up to given column, adding at least a given minimum number of spaces
/// @writer    Utf8LineMeasuringWriter.Writer
pub fn PadSpaces(writer: anytype, until: usize, min: usize) !void {
    const n: usize = @max(min, until -| writer.context.codepoints_since_newline);
    try writer.writeByteNTimes(' ', n);
}

/// A Writer that tracks how many UTF-8 codepoints have been written since the
/// previous newline character (\n)
pub fn Utf8LineMeasuringWriter(comptime WriterType: type) type {
    return struct {
        const Self = @This();

        pub const Error = WriterType.Error;
        pub const Writer = io.Writer(*Self, Error, write);

        codepoints_since_newline: usize,
        child_stream: WriterType,

        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            var amt: usize = 0;
            var line_it = std.mem.splitScalar(u8, bytes, '\n');

            const first = line_it.first();
            amt += try self.child_stream.write(first);
            self.codepoints_since_newline += std.unicode.utf8CountCodepoints(first) catch first.len;

            while (line_it.next()) |line| {
                amt += try self.child_stream.write("\n");
                amt += try self.child_stream.write(line);
                self.codepoints_since_newline = std.unicode.utf8CountCodepoints(line) catch line.len;
            }

            return amt;
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
    };
}

pub fn utf8LineMeasuringWriter(child_stream: anytype) Utf8LineMeasuringWriter(@TypeOf(child_stream)) {
    return .{ .codepoints_since_newline = 0, .child_stream = child_stream };
}

test Utf8LineMeasuringWriter {
    // no newline
    {
        var line_measuring_stream = utf8LineMeasuringWriter(std.io.null_writer);
        const stream = line_measuring_stream.writer();
        const bytes = "yay" ** 100;
        stream.writeAll(bytes) catch unreachable;
        try std.testing.expect(line_measuring_stream.codepoints_since_newline == bytes.len);
    }
    // newline
    {
        var line_measuring_stream = utf8LineMeasuringWriter(std.io.null_writer);
        const stream = line_measuring_stream.writer();
        const bytes = "yay\nyay";
        stream.writeAll(bytes) catch unreachable;
        try std.testing.expect(line_measuring_stream.codepoints_since_newline == 3);
    }
}
