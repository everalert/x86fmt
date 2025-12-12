const std = @import("std");
const builtin = @import("builtin");

// TODO: export as module

comptime {
    const req_zig = std.SemanticVersion.parse("0.13.0") catch unreachable;
    const cur_zig = builtin.zig_version;
    if (cur_zig.order(req_zig) != .eq) {
        const error_message = "Invalid Zig version ({}). Please use {}.\n";
        @compileError(std.fmt.comptimePrint(error_message, .{ cur_zig, req_zig }));
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "x86fmt",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // TESTING

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    // CLEANUP

    const clean_step = b.step("clean", "Clean up");
    clean_step.dependOn(&b.addRemoveDirTree(b.install_path).step);
    if (@import("builtin").os.tag != .windows) {
        clean_step.dependOn(&b.addRemoveDirTree(b.pathFromRoot(".zig-cache")).step);
    } else {
        clean_step.makeFn = CleanWindows;
    }
}

fn CleanWindows(_: *std.Build.Step, _: std.Progress.Node) anyerror!void {
    std.log.err("Clean step not supported on Windows. Run `./clean.bat` instead.", .{});
}
