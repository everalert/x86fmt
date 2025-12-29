const std = @import("std");

pub const VERSION_STRING = "0.1.0";
pub const VERSION = std.SemanticVersion.parse(VERSION_STRING);
