//! definition used for parsing build.zig.zon

const Dependency = struct {
    url: []const u8,
    hash: []const u8,
    lazy: bool = false,
};

name: enum { x86fmt },
version: []const u8,
fingerprint: u64,
required_zig_version: []const u8,
dependencies: struct { zbench: Dependency },
paths: []const []const u8,
