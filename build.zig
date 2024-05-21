const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    comptime {
        const current_zig = builtin.zig_version;
        const min_zig = std.SemanticVersion.parse("0.13.0-dev.230+50a141945") catch unreachable; // build system changes: ziglang/zig#19597
        if (current_zig.order(min_zig) == .lt) {
            @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
        }
    }

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{
        .default_target = .{ .abi = .musl, .os_tag = .freestanding, .cpu_arch = .wasm32 },
    });

    var basic_example = b.addExecutable(.{
        .name = "basic-example",
        .root_source_file = b.path("examples/basic.zig"),
        .target = target,
        .optimize = optimize,
    });
    basic_example.rdynamic = true;
    basic_example.entry = .disabled; // or, add an empty `pub fn main() void {}` in your code
    const pdk_module = b.addModule("extism-pdk", .{
        .root_source_file = b.path("src/main.zig"),
    });
    basic_example.root_module.addImport("extism-pdk", pdk_module);

    b.installArtifact(basic_example);
    const basic_example_step = b.step("basic_example", "Build basic_example");
    basic_example_step.dependOn(b.getInstallStep());
}
