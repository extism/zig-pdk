const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    comptime {
        const current_zig = builtin.zig_version;
        const min_zig = std.SemanticVersion.parse("0.12.0-dev.64+b835fd90c") catch unreachable; // std.json.ArrayHashMap
        if (current_zig.order(min_zig) == .lt) {
            @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
        }
    }

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{
        .default_target = .{ .abi = .musl, .os_tag = .freestanding, .cpu_arch = .wasm32 },
    });

    const pdk_module = b.addModule("extism-pdk", .{
        .source_file = .{ .path = "src/main.zig" },
    });

    var basic_example = b.addExecutable(.{
        .name = "basic-example",
        .root_source_file = .{ .path = "examples/basic.zig" },
        .target = target,
        .optimize = optimize,
    });
    basic_example.addModule("extism-pdk", pdk_module);
    basic_example.rdynamic = true;

    b.installArtifact(basic_example);
    const basic_example_step = b.step("basic_example", "Build basic_example");
    basic_example_step.dependOn(b.getInstallStep());
}
