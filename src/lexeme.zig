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

const ScopeOpener = "([{\"'`";
const ScopeCloser = ")]}\"'`";
const ScopeEscapable = [_]bool{ false, false, false, true, true, true };

// keep the stream flat since this is just for visual grouping, but this is
//  getting dangerously close to just generating an AST lol
pub fn ParseTokens(out: *std.ArrayListUnmanaged(Lexeme), tok: []const Token) void {
    var scope: ?u8 = null;
    var prev_token_kind: Token.Kind = .None;
    var start_i: usize = 0;
    for (tok, 0..) |t, i| {
        var emit_lexeme: ?Kind = null;
        defer prev_token_kind = t.kind;
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
                    if (ci != null and BLAND(
                        ScopeOpener[ci.?] == scope.?,
                        !BLAND(ScopeEscapable[ci.?], prev_token_kind == .Backslash),
                    )) {
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
    out: *std.ArrayListUnmanaged(u8),
    lex: *const Lexeme,
    i: *usize,
    ci: *usize,
    comptime BUF_SIZE_TOK: usize,
) void {
    BufAppendOpts(out, lex, i, ci, .{}, BUF_SIZE_TOK);
}

/// appends the contents of a lexeme to a byte array, advancing the provided
/// utf-8 codepoint counter
pub fn BufAppendOpts(
    out: *std.ArrayListUnmanaged(u8),
    lex: *const Lexeme,
    i: *usize,
    ci: *usize,
    opts: Lexeme.Opts,
    comptime BUF_SIZE_TOK: usize,
) void {
    switch (lex.kind) {
        .None => unreachable,
        .Separator => {
            assert(lex.data.len == 1);
            out.appendSliceAssumeCapacity(lex.data[0].data);
            out.appendAssumeCapacity(' ');
            ci.* += 1 + (std.unicode.utf8CountCodepoints(lex.data[0].data) catch unreachable);
        },
        .Word => {
            var t_kind_prev: Token.Kind = .None;
            var b_lower_emitted = false;
            for (lex.data) |t| {
                defer t_kind_prev = t.kind;

                if (BLAND(t.kind == .String, t.kind == t_kind_prev))
                    out.appendAssumeCapacity(' ');

                if (BLAND(t.kind == .String, BLOR(opts.bToLower, BLAND(opts.bHeadToLower, !b_lower_emitted)))) {
                    var buf: [BUF_SIZE_TOK]u8 = undefined;
                    const lower = std.ascii.lowerString(&buf, t.data);
                    out.appendSliceAssumeCapacity(lower);
                    b_lower_emitted = true;
                } else {
                    out.appendSliceAssumeCapacity(t.data);
                }
                ci.* += std.unicode.utf8CountCodepoints(t.data) catch unreachable;
            }
        },
    }
    i.* += 1;
}

/// appends a series of lexemes to a byte array, advancing the provided utf-8
/// codepoint counter
pub fn BufAppendSlice(
    out: *std.ArrayListUnmanaged(u8),
    lexemes: []const Lexeme,
    i: *usize,
    ci: *usize,
    opts: Lexeme.Opts,
    comptime BUF_SIZE_TOK: usize,
) void {
    var prev_kind: Lexeme.Kind = .None;
    for (lexemes, 0..) |*lex, li| {
        if (BLAND(li > 0, BLAND(lex.kind != .Separator, prev_kind != .Separator)))
            PadSpaces(out, ci, i.*);
        BufAppendOpts(out, lex, i, ci, opts, BUF_SIZE_TOK);
        prev_kind = lex.kind;
    }
}
