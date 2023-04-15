const std = @import("std");
const builtin = @import("builtin");
const Step = std.build.Step;

// TODO: make it less over-engineered
/// Create example-out when the basic_example step is called
const CreateExampleDirStep = struct {
    step: Step = undefined,
    pub fn make(step: *Step, prog_node: *std.Progress.Node) anyerror!void {
        _ = step;
        _ = prog_node;
        const make_dir_res = std.fs.cwd().makeDir("examples-out");
        if (make_dir_res == error.PathAlreadyExists) {
            return;
        }
        return make_dir_res;
    }
    pub fn addStep(b: *std.Build) *CreateExampleDirStep {
        var allocated = b.allocator.create(CreateExampleDirStep) catch unreachable;
        allocated.* = .{};
        allocated.*.step = Step.init(.{
            .id = .custom,
            .name = @typeName(CreateExampleDirStep),
            .owner = b,
            .makeFn = make,
        });
        return allocated;
    }
};

pub fn build(b: *std.Build) void {
    comptime {
        const current_zig = builtin.zig_version;
        const min_zig = std.SemanticVersion.parse("0.11.0-dev.2609+5e19250a1") catch return; // outputDir and CompileStep.install is removed
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
    basic_example.emit_bin = .{
        .emit_to = b.fmt("{s}/{s}.wasm", .{ b.pathFromRoot("examples-out"), basic_example.name }),
    };

    b.installArtifact(basic_example);
    const create_example_dir = CreateExampleDirStep.addStep(b);
    const basic_example_step = b.step("basic_example", "Build basic_example");
    basic_example_step.dependOn(&basic_example.step);
    basic_example_step.dependOn(&create_example_dir.step);
}
