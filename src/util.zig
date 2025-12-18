const std = @import("std");

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

/// Add spaces up to given column, adding a minimum of 1 space for padding
pub fn PadSpaces(out: *std.ArrayListUnmanaged(u8), col: *usize, until: usize) void {
    const n: usize = @max(1, until -| col.*);
    out.appendNTimesAssumeCapacity(32, n);
    col.* += n;
}
