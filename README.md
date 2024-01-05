# Extism Zig PDK


This library can be used to write [Extism Plug-ins](https://extism.org/docs/concepts/plug-in) in Zig.

## Install

Create a new Zig project:

```bash
mkdir my-plugin
cd my-plugin
zig init
```

Add the library as a dependency:

```zig
// build.zig.zon

.{
    .name = "my-plugin",
    .version = "0.0.0",

    .dependencies = .{
        .extism_pdk = .{
            .url = "https://github.com/extism/zig-pdk/archive/<git-ref-here>.tar.gz",
            // .hash = "" (zig build will tell you what to put here)
        },
    },

    .paths = .{""},
}

```

Change your `build.zig` so that it references `extism-pdk`:

```zig
const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    comptime {
        const current_zig = builtin.zig_version;
        const min_zig = std.SemanticVersion.parse("0.12.0-dev.2030+2ac315c24") catch unreachable;
        if (current_zig.order(min_zig) == .lt) {
            @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
        }
    }

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{
        // if you're using WASI, change the .os_tag to .wasi
        .default_target = .{ .abi = .musl, .os_tag = .freestanding, .cpu_arch = .wasm32 },
    });

    var basic_example = b.addExecutable(.{
        .name = "basic-example",
        .root_source_file = .{ .path = "examples/basic.zig" },
        .target = target,
        .optimize = optimize,
    });
    basic_example.rdynamic = true;
    basic_example.entry = .disabled; // or add an empty `pub fn main() void {}` to your code
    const pdk_module = b.addModule("extism-pdk", .{
        .root_source_file = .{ .path = "src/main.zig" },
    });
    basic_example.root_module.addImport("extism-pdk", pdk_module);

    b.installArtifact(basic_example);
    const basic_example_step = b.step("basic_example", "Build basic_example");
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

> Note: if you started with the generated project files from `zig init`, you should delete `src/root.zig`
and any references to it if they are in your `build.zig` file.

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
Suppose want to re-write our greeting module to never greet Benjamins. We can use `Plugin.setError`:

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

## Configs

Configs are key-value pairs that can be passed in by the host when creating a
plug-in. These can be useful to statically configure the plug-in with some data that exists across every function call. Here is a trivial example using `Plugin.getConfig`:

```zig
export fn greet() i32 {
    const plugin = Plugin.init(allocator);
    const user = plugin.getConfig("user") catch unreachable orelse {
        plugin.setError("This plug-in requires a 'user' key in the config");
        return 1;
    };

    const output = std.fmt.allocPrint(allocator, "Hello, {s}!", .{user}) catch unreachable;
    plugin.output(output);
    return 0;
}
```

To test it, the [Extism CLI](https://github.com/extism/cli) has a `--config` option that lets you pass in `key=value` pairs:

```bash
extism call ./zig-out/bin/my-plugin.wasm greet --config user=Benjamin
# => Hello, Benjamin!
```

## Variables

Variables are another key-value mechanism but it's a mutable data store that
will persist across function calls. These variables will persist as long as the
host has loaded and not freed the plug-in. 

```zig
export fn count() i32 {
    const plugin = Plugin.init(allocator);
    const input = plugin.getInput() catch unreachable;
    defer allocator.free(input);

    var c = plugin.getVarInt(i32, "count") catch unreachable orelse 0;

    c += 1;

    plugin.setVarInt(i32, "count", c) catch unreachable;

    const output = std.fmt.allocPrint(allocator, "{d}", .{c}) catch unreachable;
    plugin.output(output);
    return 0;
}
```

To test it, the [Extism CLI](https://github.com/extism/cli) has a `--loop` option that lets you pass call the same function multiple times:

```sh
extism call ./zig-out/bin/my-plugin.wasm count --loop 3
1
2
3
```

> **Note**: Use the untyped variants `Plugin.setVar(self: Plugin, key: []const u8, value: []const u8)` and `Plugin.getVar(self: Plugin, key: []const u8) !?[]u8` to handle your own types.

## Logging

Because Wasm modules by default do not have access to the system, printing to stdout won't work (unless you use WASI).
Extism provides a simple logging function that allows you to use the host application to log without having to give the plug-in permission to make syscalls.

```zig
export fn log_stuff() i32 {
    const plugin = Plugin.init(allocator);
    plugin.log(.Info, "An info log!");
    plugin.log(.Debug, "A debug log!");
    plugin.log(.Warn, "A warning log!");
    plugin.log(.Error, "An error log!");

    return 0;
}
```

From [Extism CLI](https://github.com/extism/cli):

```bash
extism call ./zig-out/bin/my-plugin.wasm log_stuff --log-level=debug
2023/11/22 14:00:26 Calling function : log_stuff
2023/11/22 14:00:26 An info log!
2023/11/22 14:00:26 A debug log!
2023/11/22 14:00:26 A warning log!
2023/11/22 14:00:26 An error log!
```

> *Note*: From the CLI you need to pass a level with `--log-level`. If you are running the plug-in in your own host using one of our SDKs, you need to make sure that you call `set_log_file` to `"stdout"` or some file location.

## HTTP

Sometimes it is useful to let a plug-in [make HTTP calls]. [see: Extism HTTP library](src/http.zig)

```zig
const http = extism_pdk.http;

export fn http_get() i32 {
    const plugin = Plugin.init(allocator);
    // create an HTTP request via Extism built-in function (doesn't require WASI)
    var req = http.HttpRequest.init("GET", "https://jsonplaceholder.typicode.com/todos/1");
    defer req.deinit(allocator);

    // set headers on the request object
    req.setHeader(allocator, "some-name", "some-value") catch unreachable;
    req.setHeader(allocator, "another", "again") catch unreachable;

    // make the request and get the response back
    const res = plugin.request(req, null) catch unreachable;
    defer res.deinit();

    if (res.status != 200) {
        plugin.setError("request failed");
        return @as(i32, res.status);
    }

    // get the bytes for the response body
    const body = res.body(allocator) catch unreachable;
    // => { "userId": 1, "id": 1, "title": "delectus aut autem", "completed": false }
    const Todo = struct {
        userId: u32,
        id: u32,
        title: []const u8,
        completed: bool,
    };
    const todo = std.json.parseFromSlice(Todo, allocator, body, .{}) catch |err| {
        plugin.setError(std.fmt.allocPrint(allocator, "parse error: {any}", .{err}) catch unreachable);
        return 1;
    };
    defer todo.deinit();

    // format a string with the todo data
    const t = todo.value;
    const tmpl = "[id={d}] '{s}' by user={d} is complete: {any}\n";
    const args = .{ t.id, t.title, t.userId, t.completed };
    const output = std.fmt.allocPrint(allocator, tmpl, args) catch unreachable;

    // allocate space for the output data
    const outMem = plugin.allocateBytes(output);

    // `outputMemory` provides a zero-copy way to write plugin data back to the host
    plugin.outputMemory(outMem);

    return 0;
}
```

By default, Extism modules cannot make HTTP requests unless you specify which hosts it can connect to. You can use `--allow-host` in the Extism CLI to set this:

```
extism call ./zig-out/bin/my-plugin.wasm http_get --allow-host='*.typicode.com'
# => { "userId": 1, "id": 1, "title": "delectus aut autem", "completed": false }
```

## Imports (Host Functions)

Like any other code module, Wasm not only let's you export functions to the outside world, you can
import them too. Host Functions allow a plug-in to import functions defined in the host. For example,
if you host application is written in Python, it can pass a Python function down to your Zig plug-in
where you can invoke it.

This topic can get fairly complicated and we have not yet fully abstracted the Wasm knowledge you need
to do this correctly. So we recommend reading our [concept doc on Host Functions](https://extism.org/docs/concepts/host-functions) before you get started.

### A Simple Example

Host functions have a similar interface as exports. You just need to declare them as extern. You only declare the interface as it is the host's responsibility to provide the implementation:

```zig
pub extern "extism:host/user" fn a_python_func(u64) u64;
```

We should be able to call this function as a normal Zig function. Note that we need to manually handle the pointer casting:

```zig
export fn hello_from_python() i32 {
    const plugin = Plugin.init(allocator);

    const msg = "An argument to send to Python";
    const mem = plugin.allocateBytes(msg);
    defer mem.free();

    const ptr = a_python_func(mem.offset);
    const rmem = plugin.findMemory(ptr);

    const buffer = plugin.allocator.alloc(u8, @intCast(rmem.length)) catch unreachable;
    rmem.load(buffer);
    plugin.output(buffer);

    // OR, you can directly output the memory
    // plugin.outputMemory(rmem);

    return 0;
}
```

### Testing it out

We can't really test this from the Extism CLI as something must provide the implementation. So let's
write out the Python side here. Check out the [docs for Host SDKs](https://extism.org/docs/concepts/host-sdk) to implement a host function in a language of your choice.

```python
from extism import host_fn, Function, ValType, Plugin

@host_fn
def a_python_func(plugin, input_, output, _user_data):
    # The plug-in is passing us a string
    input_str = plugin.input_string(input_[0])

    # just printing this out to prove we're in Python land
    print("Hello from Python!")

    # let's just add "!" to the input string
    # but you could imagine here we could add some
    # applicaiton code like query or manipulate the database
    # or our application APIs
    input_str += "!"

    # set the new string as the return value to the plug-in
    plugin.return_string(output[0], input_str)
```

Now when we load the plug-in we pass the host function:
 
```python
functions = [
    Function(
        "a_python_func",
        [ValType.I64],
        [ValType.I64],
        a_python_func,
        None
    )
]

manifest = {"wasm": [{"path": "/path/to/plugin.wasm"}]}
plugin = Plugin(manifest, functions=functions, wasi=True)
result = plugin.call('hello_from_python').decode('utf-8')
print(result)
```

```bash
python3 app.py
# => Hello from Python!
# => An argument to send to Python!
```

### Reach Out!

Have a question or just want to drop in and say hi? [Hop on the Discord](https://extism.org/discord)!
