const Token = @This();

const std = @import("std");
const assert = std.debug.assert;

const BLOR = @import("utl_branchless.zig").BLOR;
const BLAND = @import("utl_branchless.zig").BLAND;

// TODO: differentiate string vs identifier (vs directive, etc.)
pub const Kind = enum(u8) { None, String, Comment, MathOp, Scope, Comma, Backslash };

pub const Error = error{ CapacityExceeded, TokenSizeExceeded };

kind: Kind = .None,
data: []const u8 = &.{},

pub fn TokenizeUnicode(
    out: *std.ArrayListUnmanaged(Token),
    text: []const u8,
    comptime BUF_SIZE_TOK: usize,
) Error!void {
    var tokgen_it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (true) {
        const start_i = tokgen_it.i;
        const c_sl = tokgen_it.peek(1);
        const c = tokgen_it.nextCodepoint() orelse break;
        if (BLOR(c == ' ', c == '\t')) continue;

        var token = std.mem.zeroes(Token);
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
            '(', '[', '{', ')', ']', '}' => {
                token.kind = .Scope;
                token.data = text[start_i..tokgen_it.i];
            },
            ';' => {
                token.kind = .Comment;
                token.data = text[start_i..];
                tokgen_it.i = text.len;
            },
            '"', '\'', '`' => {
                token.kind = .String;
                token.data = text[start_i..tokgen_it.i];
                var this_sl = tokgen_it.nextCodepointSlice() orelse break;
                var b_escaped = false;
                while (true) {
                    const b_will_escape = this_sl[0] == '\\';
                    defer b_escaped = b_will_escape;
                    if (BLAND(!b_will_escape, this_sl[0] == c)) break;
                    this_sl = tokgen_it.nextCodepointSlice() orelse break;
                }
                token.data = text[start_i..tokgen_it.i];
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
                    const peek_chars = ", \t([{}])\"'`\\;";
                    if (BLOR(
                        peek_s.len == 0,
                        (peek_s.len == 1 and std.mem.indexOfScalar(u8, peek_chars, peek_s[0]) != null),
                    )) break;

                    this_sl = tokgen_it.nextCodepointSlice() orelse break;
                }
                token.data = text[start_i..tokgen_it.i];
            },
        }

        // FIXME: ideally there is no special case for comment, maybe something
        //  to reconsider when moving to a more traditional lexer later, esp.
        //  wrt where exactly the token size limit should be enforced
        // FIXME: also, BUF_SIZE_TOK should only apply to identifiers in that model
        if (BLAND(token.data.len > BUF_SIZE_TOK, token.kind != .Comment))
            return error.TokenSizeExceeded;

        if (out.unusedCapacitySlice().len == 0)
            return error.CapacityExceeded;

        out.appendAssumeCapacity(token);
    }
}

test "Tokenize" {
    const BUF_SIZE_TOK = 256;

    const TokenTestCase = struct {
        in: []const u8,
        ex: []const Token = &[_]Token{},
        err: ?Error = null,
    };

    const test_cases = [_]TokenTestCase{
        .{
            // symbol coverage
            .in = " \t,\\+-*/()[]{}\"str1\"'str2'`str3`text;comment",
            .ex = &[_]Token{
                .{ .data = ",", .kind = .Comma },
                .{ .data = "\\", .kind = .Backslash },
                .{ .data = "+", .kind = .MathOp },
                .{ .data = "-", .kind = .MathOp },
                .{ .data = "*", .kind = .MathOp },
                .{ .data = "/", .kind = .MathOp },
                .{ .data = "(", .kind = .Scope },
                .{ .data = ")", .kind = .Scope },
                .{ .data = "[", .kind = .Scope },
                .{ .data = "]", .kind = .Scope },
                .{ .data = "{", .kind = .Scope },
                .{ .data = "}", .kind = .Scope },
                .{ .data = "\"str1\"", .kind = .String },
                .{ .data = "'str2'", .kind = .String },
                .{ .data = "`str3`", .kind = .String },
                .{ .data = "text", .kind = .String },
                .{ .data = ";comment", .kind = .Comment },
            },
        },
        .{
            .in = " \t  my_label: mov eax,16; comment",
            .ex = &[_]Token{
                .{ .kind = .String, .data = "my_label:" },
                .{ .kind = .String, .data = "mov" },
                .{ .kind = .String, .data = "eax" },
                .{ .kind = .Comma, .data = "," },
                .{ .kind = .String, .data = "16" },
                .{ .kind = .Comment, .data = "; comment" },
            },
        },
        .{
            // label and colon without whitespace
            .in = "my_label:mov",
            .ex = &[_]Token{
                .{ .kind = .String, .data = "my_label:" },
                .{ .kind = .String, .data = "mov" },
            },
        },
        .{
            // deleting non-string whitespace within scope
            .in = " [ section  .text ] ",
            .ex = &[_]Token{
                .{ .kind = .Scope, .data = "[" },
                .{ .kind = .String, .data = "section" },
                .{ .kind = .String, .data = ".text" },
                .{ .kind = .Scope, .data = "]" },
            },
        },
        .{
            // string captures otherwise valid symbols/delimiters
            .in = "\"no't' c;om+ment!\"",
            .ex = &[_]Token{
                .{ .kind = .String, .data = "\"no't' c;om+ment!\"" },
            },
        },
        .{
            // comment captures otherwise valid symbols/delimiters
            .in = "; + - * /",
            .ex = &[_]Token{.{ .kind = .Comment, .data = "; + - * /" }},
        },
        .{
            // token size limit: token size overrun
            .in = "A" ** 257,
            .err = error.TokenSizeExceeded,
        },
        .{ // token size limit: longest token
            .in = "A" ** 256,
            .ex = &[_]Token{
                .{ .kind = .String, .data = "A" ** 256 },
            },
        },
    };

    std.testing.log_level = .debug;
    for (test_cases, 0..) |t, i| {
        errdefer std.debug.print("FAILED {d:0>2}\n\n", .{i});

        var output = try std.ArrayListUnmanaged(Token).initCapacity(std.testing.allocator, t.ex.len);
        defer output.deinit(std.testing.allocator);

        const result = TokenizeUnicode(&output, t.in, BUF_SIZE_TOK);

        if (t.err) |e| {
            try std.testing.expectError(e, result);
        } else {
            try result;
            try std.testing.expectEqual(t.ex.len, output.items.len);
            try std.testing.expectEqualDeep(t.ex, output.items);
        }
    }
}
