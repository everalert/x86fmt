const std = @import("std");

// TODO: confirm these actually make a difference vs natural codegen

/// branchless and -> integer
pub inline fn IBLAND(b1: bool, b2: bool) usize {
    return @intFromBool(b1) & @intFromBool(b2);
}

/// branchless and
pub inline fn BLAND(b1: bool, b2: bool) bool {
    return IBLAND(b1, b2) > 0;
}

/// branchless or -> integer
pub inline fn IBLOR(b1: bool, b2: bool) usize {
    return @intFromBool(b1) | @intFromBool(b2);
}

/// branchless or
pub inline fn BLOR(b1: bool, b2: bool) bool {
    return IBLOR(b1, b2) > 0;
}

/// add spaces up to given column, adding a minimum of 1 space for padding
pub fn PadSpaces(out: *std.ArrayListUnmanaged(u8), col: *usize, until: usize) void {
    const n: usize = @max(1, until -| col.*);
    out.appendNTimesAssumeCapacity(32, n);
    col.* += n;
}
