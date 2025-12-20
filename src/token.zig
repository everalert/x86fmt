const Token = @This();

const std = @import("std");
const assert = std.debug.assert;

const BLOR = @import("util.zig").BLOR;

pub const Kind = enum(u8) { None, String, MathOp, Scope, Comma, Backslash, Whitespace };

kind: Kind = .None,
data: []const u8 = &[_]u8{},

pub fn TokenizeUnicode(
    out: *std.ArrayListUnmanaged(Token),
    text: []const u8,
) error{CapacityExceeded}!void {
    var tokgen_it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (true) {
        const start_i = tokgen_it.i;
        const c_sl = tokgen_it.peek(1);
        const c = tokgen_it.nextCodepoint() orelse break;

        if (out.unusedCapacitySlice().len == 0) return error.CapacityExceeded;
        var token: *Token = out.addOneAssumeCapacity();

        switch (c) {
            ',' => {
                token.kind = .Comma;
                token.data = text[start_i..tokgen_it.i];
            },
            '\\' => {
                token.kind = .Backslash;
                token.data = text[start_i..tokgen_it.i];
            },
            '+', '-', '*', '/' => {
                token.kind = .MathOp;
                token.data = text[start_i..tokgen_it.i];
            },
            '(', '[', '{', ')', ']', '}', '\"', '\'', '`' => {
                token.kind = .Scope;
                token.data = text[start_i..tokgen_it.i];
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
                _ = out.pop();
            },
            else => {
                token.kind = .String;
                var this_sl = c_sl;
                while (true) {
                    // split on string-ending char
                    const split_chars = ":";
                    if (std.mem.indexOfScalar(u8, split_chars, this_sl[0]) != null) break;

                    // split on token-starting char
                    const peek_s = tokgen_it.peek(1);
                    const peek_chars = ", \t([{}])\"'`\\";
                    if (BLOR(
                        peek_s.len == 0,
                        (peek_s.len == 1 and std.mem.indexOfScalar(u8, peek_chars, peek_s[0]) != null),
                    )) break;

                    this_sl = tokgen_it.nextCodepointSlice() orelse break;
                }
                token.data = text[start_i..tokgen_it.i];
            },
        }
    }
}
