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
    const opts = GlobalOptions.Init(b);

    export_module(b, "x86fmt", "src/root.zig");

    // TODO: return module from this, and feed into build_binary and build_tests
    step_release(b, &opts, &.{});
    step_install(b, &opts, &.{});
    step_all_tests(b, &opts);
    step_clean(b);
}

// OUTPUT

fn step_release(
    b: *Build,
    opts: *const GlobalOptions,
    imports: []const ModuleImport,
) void {
    const step = b.step("release", "make an upstream binary release");

    const release_targets = [_]std.Target.Query{
        .{ .os_tag = .linux, .cpu_arch = .aarch64 },
        .{ .os_tag = .linux, .cpu_arch = .x86_64 },
        .{ .os_tag = .linux, .cpu_arch = .x86 },
        .{ .os_tag = .linux, .cpu_arch = .riscv64 },
        .{ .os_tag = .windows, .cpu_arch = .x86_64 },
        .{ .os_tag = .windows, .cpu_arch = .x86 },
        //.{ .os_tag = .windows, .cpu_arch = .arm },
    };

    for (release_targets) |target_query| {
        const target = b.resolveTargetQuery(target_query);
        const bin = b.addExecutable(.{
            .name = "x86fmt",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .imports = imports,
                .target = target,
                .optimize = .ReleaseFast,
                .strip = true,
                .single_threaded = true,
            }),
        });

        bin.root_module.addAnonymousImport("build.zig.zon", .{ .root_source_file = b.path("build.zig.zon") });

        if (opts.NoBin) {
            step.dependOn(&bin.step);
            continue;
        }

        const t = target.result;
        const install = b.addInstallArtifact(bin, .{});
        install.dest_dir = .prefix;
        install.dest_sub_path = b.fmt(
            "release/{t}-{t}-{s}",
            .{ t.os.tag, t.cpu.arch, install.dest_sub_path },
        );

        if (opts.Asm) {
            const assembly = b.addInstallBinFile(bin.getEmittedAsm(), b.fmt("{s}.s", .{install.dest_sub_path}));
            step.dependOn(&assembly.step);
        }

        step.dependOn(&install.step);
    }
}

fn export_module(b: *Build, name: []const u8, path: []const u8) void {
    _ = b.addModule(name, .{ .root_source_file = b.path(path) });
}

fn step_install(
    b: *Build,
    opts: *const GlobalOptions,
    imports: []const ModuleImport,
) void {
    const step = b.getInstallStep();

    const bin = b.addExecutable(.{
        .name = "x86fmt",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .imports = imports,
            .target = opts.Target,
            .optimize = opts.Optimize,
            .strip = opts.Strip,
            .single_threaded = true,
        }),
    });

    if (opts.Asm) {
        const assembly = b.addInstallBinFile(bin.getEmittedAsm(), "x86fmt.s");
        step.dependOn(&assembly.step);
    }

    // TODO: move to general "global imports" thing similar to GlobalOptions; do
    //  same for imports in other step functions
    //const module_opts = .{
    //    .target = target,
    //    .optimize = optimize,
    //    .strip = small_out,
    //    .single_threaded = true,
    //};
    //const zbench_module = b.dependency("zbench", module_opts).module("zbench");
    //exe.root_module.addImport("zbench", zbench_module);
    bin.root_module.addAnonymousImport("build.zig.zon", .{ .root_source_file = b.path("build.zig.zon") });

    if (opts.NoBin) {
        step.dependOn(&bin.step);
    } else {
        b.installArtifact(bin);
    }
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
    imports: []const ModuleImport,
};

fn step_single_test(
    b: *Build,
    opts: *const GlobalOptions,
    testdef: TestDef,
) void {
    const step = b.step(testdef.name, testdef.desc);

    const compile = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(testdef.entry),
            .imports = testdef.imports,
            .target = opts.Target,
            .optimize = opts.Optimize,
        }),
    });

    if (opts.NoRun) {
        step.dependOn(&compile.step);
    } else {
        const run = b.addRunArtifact(compile);
        step.dependOn(&run.step);
    }
}

fn step_all_tests(
    b: *Build,
    opts: *const GlobalOptions,
) void {
    const imports_embeds: []const ModuleImport = blk: {
        const files: []const struct { []const u8, []const u8 } = &.{
            .{ "build.zig.zon", "build.zig.zon" },
            .{ "testfile_app_all", "testing/app.all.asmtest" },
            .{ "testfile_app_base", "testing/app.base.asmtest" },
            .{ "testfile_app_default", "testing/app.default.asmtest" },
            .{ "testfile_fmt_all", "testing/fmt.all.asmtest" },
            .{ "testfile_fmt_base", "testing/fmt.base.asmtest" },
            .{ "testfile_fmt_default", "testing/fmt.default.asmtest" },
        };
        var modules: [files.len]ModuleImport = undefined;
        for (files, 0..) |file, i| modules[i] = .{
            .name = file.@"0",
            .module = b.createModule(.{ .root_source_file = b.path(file.@"1") }),
        };
        break :blk &modules;
    };

    step_single_test(b, opts, .{
        .name = "test",
        .desc = "Run all tests, including tests not covered by test-exe or test-module",
        .entry = "src/test.zig",
        .imports = imports_embeds,
    });

    step_single_test(b, opts, .{
        .name = "test-exe",
        .desc = "Run executable tests",
        .entry = "src/main.zig",
        .imports = imports_embeds,
    });

    step_single_test(b, opts, .{
        .name = "test-fmt",
        .desc = "Run formatter tests",
        .entry = "src/root.zig",
        .imports = imports_embeds,
    });
}

// CLEANUP / BUILD UTIL

fn step_clean(b: *Build) void {
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

// GLOBAL OPTIONS

const GlobalOptions = struct {
    Target: ResolvedTarget,
    Optimize: OptimizeMode,
    NoBin: bool,
    NoRun: bool,
    Strip: bool,
    Asm: bool,

    pub fn Init(b: *Build) GlobalOptions {
        return .{
            .Target = b.standardTargetOptions(.{}),
            .Optimize = b.standardOptimizeOption(.{}),
            .NoBin = b.option(bool, "no-bin", "skip emitting binary") orelse false,
            .NoRun = b.option(bool, "no-run", "skip running tests") orelse false,
            .Strip = b.option(bool, "strip", "strip the binary") orelse false,
            .Asm = b.option(bool, "asm", "emit assembly alongside binary") orelse false,
        };
    }
};
