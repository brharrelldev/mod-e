const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const brain_entry = b.createModule(.{
        .root_source_file = b.path("src/brain_main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_brain_entry = b.addExecutable(.{
        .name = "mod-e",
        .root_module = brain_entry,
    });

    b.installArtifact(exe_brain_entry);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe_brain_entry);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib");
    const raylib_gui = raylib_dep.module("raygui");
    const raylib_artififact = raylib_dep.artifact("raylib");

    exe_brain_entry.linkLibrary(raylib_artififact);

    exe_brain_entry.root_module.addImport("raylib", raylib);
    exe_brain_entry.root_module.addImport("raygui", raylib_gui);
}
