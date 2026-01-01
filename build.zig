const std = @import("std");
const builtin = @import("builtin");

const manifest: struct {
    const Dependency = struct { url: []const u8, hash: []const u8, lazy: bool = false };
    name: enum { x86fmt },
    version: []const u8,
    fingerprint: u64,
    required_zig_version: []const u8,
    dependencies: struct { zbench: Dependency },
    paths: []const []const u8,
} = @import("build.zig.zon");

comptime {
    const req_zig = std.SemanticVersion.parse(manifest.required_zig_version) catch unreachable;
    const cur_zig = builtin.zig_version;
    if (cur_zig.order(req_zig) != .eq) {
        const error_message = "Invalid Zig version ({}). Please use {}.\n";
        @compileError(std.fmt.comptimePrint(error_message, .{ cur_zig, req_zig }));
    }
}

// TODO: export as module

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    build_exe(b, target, optimize);
    build_step_tests(b, target, optimize);
    build_step_cleanup(b);
}

fn build_exe(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const module_opts = .{ .target = target, .optimize = optimize };
    const zbench_module = b.dependency("zbench", module_opts).module("zbench");

    const exe = b.addExecutable(.{
        .name = "x86fmt",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zbench", zbench_module);
    b.installArtifact(exe);
}

fn build_step_tests(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const test_step = b.step("test", "Run unit tests");

    const testfiles = [_]struct { []const u8, std.Build.Module.CreateOptions }{
        .{ "testfile_app_all", .{ .root_source_file = b.path("testing/app.all.asmtest") } },
        .{ "testfile_app_base", .{ .root_source_file = b.path("testing/app.base.asmtest") } },
        .{ "testfile_app_default", .{ .root_source_file = b.path("testing/app.default.asmtest") } },
        .{ "testfile_fmt_all", .{ .root_source_file = b.path("testing/fmt.all.asmtest") } },
        .{ "testfile_fmt_base", .{ .root_source_file = b.path("testing/fmt.base.asmtest") } },
        .{ "testfile_fmt_default", .{ .root_source_file = b.path("testing/fmt.default.asmtest") } },
    };

    const tests_compile = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    for (testfiles) |testfile|
        tests_compile.root_module.addAnonymousImport(testfile[0], testfile[1]);

    const tests_run = b.addRunArtifact(tests_compile);

    test_step.dependOn(&tests_run.step);
}

fn build_step_cleanup(b: *std.Build) void {
    const clean_step = b.step("clean", "Clean up");

    clean_step.dependOn(&b.addRemoveDirTree(.{ .cwd_relative = b.install_path }).step);
    if (@import("builtin").os.tag != .windows) {
        clean_step.dependOn(&b.addRemoveDirTree(b.pathFromRoot(".zig-cache")).step);
    } else {
        clean_step.makeFn = CleanWindows;
    }
}

fn CleanWindows(_: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
    std.log.err("Clean step not supported on Windows. Run `./clean.bat` instead.", .{});
}
