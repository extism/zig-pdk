# Extism Zig PDK


This library can be used to write [Extism Plug-ins](https://extism.org/docs/concepts/plug-in) in Zig.

## Install

Generate a `lib` project with Zig:

```bash
mkdir my-plugin
cd ./my-plugin
zig init-lib
```

Add the library as a dependency:

```bash
mkdir -p libs
cd libs
git clone https://github.com/extism/zig-pdk.git
```

Change your `build.zig` so that it references `extism-pdk`:

```zig
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
        .source_file = .{ .path = "libs/zig-pdk/src/main.zig" },
    });

    var basic_example = b.addExecutable(.{
        .name = "my-plugin",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    basic_example.addModule("extism-pdk", pdk_module);
    basic_example.rdynamic = true;

    b.installArtifact(basic_example);
    const basic_example_step = b.step("my-plugin", "Build my-plugin");
    basic_example_step.dependOn(b.getInstallStep());
}
```

## Getting Started

The goal of writing an [Extism plug-in](https://extism.org/docs/concepts/plug-in) is to compile your Zig code to a Wasm module with exported functions that the host application can invoke. The first thing you should understand is creating an export. Let's write a simple program that exports a `greet` function which will take a name as a string and return a greeting string. Zig has excellent support for this through the `export` keyword:

```zig
const std = @import("std");
const extism_pdk = @import("extism-pdk");
const Plugin = extism_pdk.Plugin;

const allocator = std.heap.wasm_allocator;

export fn greet() i32 {
    const plugin = Plugin.init(allocator);
    const name = plugin.getInput() catch unreachable;
    defer allocator.free(name);

    const output = std.fmt.allocPrint(allocator, "Hello, {s}!", .{name}) catch unreachable;
    plugin.output(output);
    return 0;
}
```

Then run:
```sh
zig build
```

This will put your compiled wasm in `zig-out/bin`.
We can now test it using the [Extism CLI](https://github.com/extism/cli)'s `run`
command:

```bash
extism call ./zig-out/bin/my-plugin.wasm greet --input "Benjamin"
# => Hello, Benjamin!
```

> **Note**: We also have a web-based, plug-in tester called the [Extism Playground](https://playground.extism.org/)

### More Exports: Error Handling
Suppose want to re-write our greeting module to never greet Benjamins. We can use `plugin.setError`:

```zig
export fn greet() i32 {
    const plugin = Plugin.init(allocator);
    const name = plugin.getInput() catch unreachable;
    defer allocator.free(name);

    if (std.mem.eql(u8, name, "Benjamin")) {
        plugin.setError("Sorry, we don't greet Benjamins!");
        return 1;
    }

    const output = std.fmt.allocPrint(allocator, "Hello, {s}!", .{name}) catch unreachable;
    plugin.output(output);
    return 0;
}
```

Now when we try again:

```bash
extism call ./zig-out/bin/my-plugin.wasm greet --input="Benjamin"
# => Error: Sorry, we don't greet Benjamins!
echo $? # print last status code
# => 1
extism call ./zig-out/bin/my-plugin.wasm greet --input="Zach"
# => Hello, Zach!
echo $?
# => 0
```

### Json

Extism export functions simply take bytes in and bytes out. Those can be whatever you want them to be. A common and simple way to get more complex types to and from the host is with json:

```zig
export fn add() i32 {
    const Add = struct {
        a: i32,
        b: i32,
    };

    const Sum = struct {
        sum: i32,
    };

    const plugin = Plugin.init(allocator);
    const input = plugin.getInput() catch unreachable;
    defer allocator.free(input);

    const params = std.json.parseFromSlice(Add, allocator, input, std.json.ParseOptions{}) catch unreachable;
    const sum = Sum{ .sum = params.value.a + params.value.b };

    const output = std.json.stringifyAlloc(allocator, sum, std.json.StringifyOptions{}) catch unreachable;
    plugin.output(output);
    return 0;
}
```

```bash
extism call ./zig-out/bin/my-plugin.wasm add --input='{"a": 20, "b": 21}'
# => {"sum":41}
```

Join the [Discord](https://discord.gg/cx3usBCWnc) and chat with us!
