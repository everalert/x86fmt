const std = @import("std");
const Manifest = @import("app_manifest.zig");
const manifest: Manifest = @import("build.zig.zon");

pub const VERSION_STRING = manifest.version;
pub const VERSION = std.SemanticVersion.parse(manifest.version) catch unreachable;
