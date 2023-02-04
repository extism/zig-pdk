const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{ 
        .default_target = .{ .abi = .musl, .os_tag = .freestanding, .cpu_arch = .wasm32 },
    });

    const lib = b.addStaticLibrary(.{
        .name = "extism-pdk",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.install();

    var basic_example = b.addExecutable(.{
        .name = "Basic example",
        .root_source_file = .{ .path = "examples/basic.zig" },
        .target = target,
        .optimize = optimize,
    });
    basic_example.addPackagePath("extism-pdk", "src/main.zig");
    basic_example.rdynamic = true;
    basic_example.setOutputDir("examples-out");

    const basic_example_step = b.step("basic_example", "Build basic_example");
    basic_example_step.dependOn(&basic_example.step);
}
