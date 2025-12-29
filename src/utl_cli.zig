const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const eql = std.mem.eql;

const BLAND = @import("utl_branchless.zig").BLAND;

// all helpers return whether they got a "hit" on a cli flag, indicating that the
// parsing loop can short circuit

/// parse argument as value to the previous argument
pub fn StageTwoCheck(
    alloc: Allocator,
    arg: []const u8,
    stage1_triggered: bool, // use result from your regular checker here
    comptime ValT: type,
    out: *ValT,
    out_default: ValT,
    b_waiting: *bool,
) bool {
    if (b_waiting.*) {
        if (ValueCheckOnce(ValT, out.*, out_default)) {
            switch (@typeInfo(ValT)) {
                .Pointer => |t| {
                    comptime assert(t.is_const);
                    comptime assert(t.child == u8);
                    comptime assert(t.size == .Slice);
                    out.* = alloc.dupe(u8, arg) catch out.*;
                },
                .Int => |t| {
                    comptime assert(t.signedness == .unsigned);
                    // overflow or wrong sign falls back to existing value
                    out.* = std.fmt.parseUnsigned(ValT, arg, 0) catch out.*;
                },
                else => @compileError("unsupported type"),
            }
        }
        b_waiting.* = false;
        return true;
    }

    b_waiting.* = stage1_triggered;
    return stage1_triggered;
}

/// sets a bool to true if argument matches any, skipping if the bool is already
/// set true
pub fn BoolCheckOnce(
    arg: []const u8,
    comptime flags: []const []const u8,
    out: *bool,
) bool {
    if (out.*) return false;
    inline for (flags) |flag| if (eql(u8, arg, flag)) {
        out.* = true;
        return true;
    };
    return false;
}

/// sets a nullable enum to a given value if argument matches any, skipping if
/// the enum is already set
pub fn EnumCheckOnce(
    arg: []const u8,
    comptime flags: []const []const u8,
    comptime T: type,
    val: T,
    out: *?T,
) bool {
    if (out.* != null) return false;
    inline for (flags) |flag| if (eql(u8, arg, flag)) {
        out.* = val;
        return true;
    };
    return false;
}

/// match an argument against a list of flags
pub fn RawCheck(arg: []const u8, comptime flags: []const []const u8) bool {
    inline for (flags) |flag|
        if (eql(u8, arg, flag)) return true;
    return false;
}

/// check if a value is settable (it is not already set)
pub fn ValueCheckOnce(comptime T: type, value: T, default: T) bool {
    switch (@typeInfo(T)) {
        .Pointer => |t| {
            comptime assert(t.is_const);
            comptime assert(t.child == u8);
            comptime assert(t.size == .Slice);
            return BLAND(value.len == default.len, value.ptr == default.ptr);
        },
        .Int => |t| {
            comptime assert(t.signedness == .unsigned);
            return value == default;
        },
        else => @compileError("unsupported type"),
    }
}
