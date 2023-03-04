const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    comptime {
        const current_zig = builtin.zig_version;
        const min_zig = std.SemanticVersion.parse("0.11.0-dev.1817+f6c934677") catch return; // package manager hashes made consistent on windows
        if (current_zig.order(min_zig) == .lt) {
            @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
        }
    }
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{
        .default_target = .{ .abi = .musl, .os_tag = .freestanding, .cpu_arch = .wasm32 },
    });

    b.addModule(.{
        .name = "extism-pdk",
        .source_file = .{ .path = "src/main.zig" },
    });

    // const pdk_module = b.createModule(.{
    //     .source_file = .{ .path = "src/main.zig" },
    // });
    // const lib = b.addStaticLibrary(.{
    //     .name = "extism-pdk",
    //     .root_source_file = .{ .path = "src/main.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });
    // lib.install();

    var basic_example = b.addExecutable(.{
        .name = "Basic example",
        .root_source_file = .{ .path = "examples/basic.zig" },
        .target = target,
        .optimize = optimize,
    });
    // basic_example.addModule("extism-pdk", pdk_module);
    basic_example.addAnonymousModule("extism-pdk", .{ .source_file = .{ .path = "src/main.zig" } });
    basic_example.rdynamic = true;
    basic_example.setOutputDir("examples-out");

    const basic_example_step = b.step("basic_example", "Build basic_example");
    basic_example_step.dependOn(&basic_example.step);
}
