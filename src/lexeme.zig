const Lexeme = @This();

const std = @import("std");
const assert = std.debug.assert;

const Token = @import("token.zig");
const BLAND = @import("util.zig").BLAND;
const BLOR = @import("util.zig").BLOR;
const PadSpaces = @import("util.zig").PadSpaces;

pub const Kind = enum(u8) { None, Word, Separator };

pub const Opts = packed struct(u32) {
    bToLower: bool = false,
    bHeadToLower: bool = false,
    _: u30 = 0,
};

kind: Kind = .None,
data: []const Token,

const ScopeOpener = "([{";
const ScopeCloser = ")]}";

// keep the stream flat since this is just for visual grouping, but this is
//  getting dangerously close to just generating an AST lol
pub fn ParseTokens(
    out: *std.ArrayListUnmanaged(Lexeme),
    tok: []const Token,
) error{CapacityExceeded}!void {
    var scope: ?u8 = null;
    var start_i: usize = 0;
    for (tok, 0..) |t, i| {
        if (out.items.len >= out.capacity) return error.CapacityExceeded;

        var emit_lexeme: ?Kind = null;
        defer if (emit_lexeme) |k| {
            var lexeme: *Lexeme = out.addOneAssumeCapacity();
            lexeme.kind = k;
            lexeme.data = tok[start_i .. i + 1];
            start_i = i + 1;
        };

        switch (t.kind) {
            .None, .Whitespace => unreachable,
            .Scope => {
                if (scope != null) {
                    const ci = std.mem.indexOfScalar(u8, ScopeCloser, t.data[0]);
                    if (BLAND(ci != null, ScopeOpener[ci.?] == scope.?)) {
                        scope = null;
                        emit_lexeme = .Word;
                    }
                    continue;
                }
                const oi = std.mem.indexOfScalar(u8, ScopeOpener, t.data[0]);
                if (oi != null) scope = t.data[0];
            },
            .Comma, .Backslash, .String, .MathOp => |k| {
                if (scope != null) continue;
                switch (k) {
                    .Comma, .Backslash => {
                        emit_lexeme = .Separator;
                    },
                    .String, .MathOp => {
                        emit_lexeme = .Word;
                    },
                    else => unreachable,
                }
            },
        }
    }
}

/// appends the contents of a lexeme to a byte array, advancing the provided
/// utf-8 codepoint counter
pub inline fn BufAppend(
    writer: anytype, // Utf8LineMeasuringWriter.Writer
    lex: *const Lexeme,
    i: *usize,
    comptime BUF_SIZE_TOK: usize,
) !void {
    try BufAppendOpts(writer, lex, i, .{}, BUF_SIZE_TOK);
}

/// appends the contents of a lexeme to a byte array, advancing the provided
/// utf-8 codepoint counter
pub fn BufAppendOpts(
    writer: anytype, // Utf8LineMeasuringWriter.Writer
    lex: *const Lexeme,
    i: *usize,
    opts: Lexeme.Opts,
    comptime BUF_SIZE_TOK: usize,
) !void {
    switch (lex.kind) {
        .None => unreachable,
        .Separator => {
            assert(lex.data.len == 1);
            _ = try writer.write(lex.data[0].data);
            try writer.writeByte(' ');
        },
        .Word => {
            var t_kind_prev: Token.Kind = .None;
            var b_lower_emitted = false;
            for (lex.data) |t| {
                assert(t.data.len <= BUF_SIZE_TOK);
                defer t_kind_prev = t.kind;

                if (BLAND(t.kind == .String, t.kind == t_kind_prev))
                    try writer.writeByte(' ');

                if (BLAND(t.kind == .String, BLOR(opts.bToLower, BLAND(opts.bHeadToLower, !b_lower_emitted)))) {
                    var buf: [BUF_SIZE_TOK]u8 = undefined;
                    const lower = std.ascii.lowerString(&buf, t.data);
                    _ = try writer.write(lower);
                    b_lower_emitted = true;
                } else {
                    _ = try writer.write(t.data);
                }
            }
        },
    }
    i.* += 1;
}

/// appends a series of lexemes to a byte array, advancing the provided utf-8
/// codepoint counter
pub fn BufAppendSlice(
    writer: anytype, // Utf8LineMeasuringWriter.Writer
    lexemes: []const Lexeme,
    i: *usize,
    opts: Lexeme.Opts,
    comptime BUF_SIZE_TOK: usize,
) !void {
    var prev_kind: Lexeme.Kind = .None;
    for (lexemes, 0..) |*lex, li| {
        if (BLAND(li > 0, BLAND(lex.kind != .Separator, prev_kind != .Separator)))
            try PadSpaces(writer, i.*, 1);
        try BufAppendOpts(writer, lex, i, opts, BUF_SIZE_TOK);
        prev_kind = lex.kind;
    }
}
