const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    comptime {
        const current_zig = builtin.zig_version;
        const min_zig = std.SemanticVersion.parse("0.11.0-dev.1856+653814f76") catch return; // addModule returns the created Module
        if (current_zig.order(min_zig) == .lt) {
            @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
        }
    }

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{
        .default_target = .{ .abi = .musl, .os_tag = .freestanding, .cpu_arch = .wasm32 },
    });

    const tres_module = b.dependency("tres", .{}).module("tres");

    const pdk_module = b.addModule("extism-pdk", .{
        .source_file = .{ .path = "src/main.zig" },
        .dependencies = &.{
            .{ .name = "tres", .module = tres_module },
        },
    });

    var basic_example = b.addExecutable(.{
        .name = "Basic example",
        .root_source_file = .{ .path = "examples/basic.zig" },
        .target = target,
        .optimize = optimize,
    });
    basic_example.addModule("extism-pdk", pdk_module);
    basic_example.rdynamic = true;
    basic_example.setOutputDir("examples-out");

    const basic_example_step = b.step("basic_example", "Build basic_example");
    basic_example_step.dependOn(&basic_example.step);
}
