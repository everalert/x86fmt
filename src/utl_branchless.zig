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
