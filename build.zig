const std = @import("std");
const builtin = @import("builtin");

const Build = std.Build;
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;
const Step = Build.Step;
const StepMakeOptions = Build.Step.MakeOptions;
const Module = Build.Module;
const ModuleCreateOptions = Build.Module.CreateOptions;
const ModuleImport = Module.Import;

const manifest: @import("src/app_manifest.zig") = @import("build.zig.zon");

comptime {
    const req_zig = std.SemanticVersion.parse(manifest.required_zig_version) catch unreachable;
    const cur_zig = builtin.zig_version;
    if (cur_zig.order(req_zig) != .eq) {
        const error_message = "Invalid Zig version ({f}). Please use {f}.\n";
        @compileError(std.fmt.comptimePrint(error_message, .{ cur_zig, req_zig }));
    }
}

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // TODO: return module from this, and feed into build_binary and build_tests
    build_module(b, "x86fmt", "src/root.zig");
    build_binary(b, target, optimize, &.{});
    build_clean(b);
    build_tests(b, target, optimize);
}

// OUTPUT

fn build_module(b: *Build, name: []const u8, path: []const u8) void {
    _ = b.addModule(name, .{ .root_source_file = b.path(path) });
}

fn build_binary(
    b: *Build,
    target: ResolvedTarget,
    optimize: OptimizeMode,
    imports: []const ModuleImport,
) void {
    const small_out: bool = optimize == .ReleaseFast or optimize == .ReleaseSmall;

    const bin = b.addExecutable(.{
        .name = "x86fmt",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .imports = imports,
            .target = target,
            .optimize = optimize,
            .strip = small_out,
            .single_threaded = true,
        }),
    });

    //const module_opts = .{
    //    .target = target,
    //    .optimize = optimize,
    //    .strip = small_out,
    //    .single_threaded = true,
    //};
    //const zbench_module = b.dependency("zbench", module_opts).module("zbench");
    //exe.root_module.addImport("zbench", zbench_module);

    bin.root_module.addAnonymousImport("build.zig.zon", .{ .root_source_file = b.path("build.zig.zon") });

    b.installArtifact(bin);
}

// TESTS

const TestEmbed = struct {
    []const u8,
    ModuleCreateOptions,
};

const TestDef = struct {
    name: []const u8,
    desc: []const u8,
    entry: []const u8,
    embeds: []const TestEmbed,
};

fn build_single_test(b: *Build, target: ResolvedTarget, optimize: OptimizeMode, testdef: TestDef) void {
    const step = b.step(testdef.name, testdef.desc);

    const compile = b.addTest(.{
        .root_source_file = b.path(testdef.entry),
        .target = target,
        .optimize = optimize,
    });

    for (testdef.embeds) |embed|
        compile.root_module.addAnonymousImport(embed[0], embed[1]);

    const run = b.addRunArtifact(compile);

    step.dependOn(&run.step);
}

fn build_tests(b: *Build, target: ResolvedTarget, optimize: OptimizeMode) void {
    const embeds = &[_]TestEmbed{
        .{ "build.zig.zon", .{ .root_source_file = b.path("build.zig.zon") } },
        .{ "testfile_app_all", .{ .root_source_file = b.path("testing/app.all.asmtest") } },
        .{ "testfile_app_base", .{ .root_source_file = b.path("testing/app.base.asmtest") } },
        .{ "testfile_app_default", .{ .root_source_file = b.path("testing/app.default.asmtest") } },
        .{ "testfile_fmt_all", .{ .root_source_file = b.path("testing/fmt.all.asmtest") } },
        .{ "testfile_fmt_base", .{ .root_source_file = b.path("testing/fmt.base.asmtest") } },
        .{ "testfile_fmt_default", .{ .root_source_file = b.path("testing/fmt.default.asmtest") } },
    };

    build_single_test(b, target, optimize, .{
        .name = "test",
        .desc = "Run all tests, including tests not covered by test-exe or test-module",
        .entry = "src/test.zig",
        .embeds = embeds,
    });

    build_single_test(b, target, optimize, .{
        .name = "test-exe",
        .desc = "Run executable tests",
        .entry = "src/main.zig",
        .embeds = embeds,
    });

    build_single_test(b, target, optimize, .{
        .name = "test-fmt",
        .desc = "Run formatter tests",
        .entry = "src/root.zig",
        .embeds = embeds,
    });
}

// CLEANUP / BUILD UTIL

fn build_clean(b: *Build) void {
    const step = b.step("clean", "Remove build system artifacts");

    step.dependOn(&b.addRemoveDirTree(.{ .cwd_relative = b.install_path }).step);

    if (builtin.os.tag != .windows) {
        step.dependOn(&b.addRemoveDirTree(.{ .cwd_relative = ".zig-cache" }).step);
    } else {
        step.makeFn = CleanWindows;
    }
}

fn CleanWindows(_: *Step, _: StepMakeOptions) anyerror!void {
    // Windows locks `.zig-cache` during build, so we have to clean it outside the build system
    std.log.err("Cannot remove `.zig-cache` during build process on Windows. Run `./clean.bat`", .{});
}
