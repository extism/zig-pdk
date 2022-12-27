const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding } });

    const lib = b.addStaticLibrary("extism-pdk", "src/main.zig");
    lib.setBuildMode(mode);
    lib.addIncludePath("src/");
    lib.install();

    const main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    var basic_example = b.addExecutable("Basic example", "examples/basic.zig");
    basic_example.addPackagePath("extism-pdk", "src/main.zig");
    basic_example.setTarget(target);
    basic_example.setBuildMode(mode);
    basic_example.setOutputDir("examples-out");

    const basic_example_step = b.step("basic_example", "Build basic_example");
    basic_example_step.dependOn(&basic_example.step);
}
