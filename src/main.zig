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

    Format(alloc, stdi_br.reader(), stdo_bw.writer(), .{});
}

const FormatSettings = struct {};

const BOM = [3]u8{ 0xEF, 0xBB, 0xBF };

// NOTE: NASM accepts only non-extended ASCII or UTF-8 without BOM; in other
//  words, it only accepts plain UTF-8
// TODO: decide whether or not an allocator is actually appropriate to provide
//  the scratch buffer
/// @alloc  used to allocate scratch buffer
/// @i      Reader to NASM source code, in a UTF-8 compatible byte stream
/// @o      Writer to the formatted code's destination byte stream
pub fn Format(alloc: Allocator, i: anytype, o: anytype, settings: FormatSettings) void {
    _ = alloc;
    _ = i;
    _ = o;
    _ = settings;
}

test "initial test to get things going plis rework/rename this later or else bro" {
    const alloc = std.testing.allocator;

    // simple standard line with all elements
    // tab_size:4  labeled_instr_col:12  comment_col:40
    const data_i = "   my_label: mov eax,16;comment";
    const data_e = "my_label:   mov     eax, 16             ; comment";

    var input = std.io.fixedBufferStream(data_i);

    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    Format(alloc, input.reader(), output.writer(), .{});

    try std.testing.expectEqualStrings(data_e, output.items);
}
