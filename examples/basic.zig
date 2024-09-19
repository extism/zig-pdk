const std = @import("std");
const extism_pdk = @import("extism-pdk");
const Plugin = extism_pdk.Plugin;
const http = extism_pdk.http;

const allocator = std.heap.wasm_allocator;

// define some type to write as output from the plugin back to the host
const Output = struct {
    count: i32,
    config: []const u8,
    a: []const u8,
};

export fn count_vowels() i32 {
    const plugin = Plugin.init(allocator);
    plugin.log(.Debug, "plugin start");
    const input = plugin.getInput() catch unreachable;
    defer allocator.free(input);
    plugin.log(.Debug, "plugin input");
    var vowelsCount: i32 = 0;
    for (input) |char| {
        switch (char) {
            'A', 'I', 'E', 'O', 'U', 'a', 'e', 'i', 'o', 'u' => vowelsCount += 1,
            else => {},
        }
    }

    // use persistent variables owned by a plugin instance (stored in-memory between function calls)
    const var_a_optional = plugin.getVar("a") catch unreachable;
    plugin.log(.Debug, "plugin var get");

    if (var_a_optional == null) {
        plugin.setVar("a", "this is var a");
        plugin.log(.Debug, "plugin var set");
    } else {
        allocator.free(var_a_optional.?);
    }
    const var_a = plugin.getVar("a") catch unreachable orelse "";
    defer allocator.free(var_a);

    // access host-provided configuration (key/value)
    const thing = plugin.getConfig("thing") catch unreachable orelse "<unset by host>";
    plugin.log(.Debug, "plugin config get");

    const data = Output{ .count = vowelsCount, .config = thing, .a = var_a };
    const output = std.json.stringifyAlloc(allocator, data, .{}) catch unreachable;
    defer allocator.free(output);
    plugin.log(.Debug, "plugin json encoding");

    // write the plugin data back to the host
    plugin.output(output);
    plugin.log(.Debug, "plugin output");

    return 0;
}

const Input = struct {
    name: []const u8,
    age: u16,
};

export fn json_input() i32 {
    const plugin = Plugin.init(allocator);
    // plugin.getJson() is opinionated about parsing and manages the alloc/free for you
    // alternatively, plugin.getJsonOpt() let's you control parse options
    const input = plugin.getJson(Input) catch unreachable;
    const out = std.fmt.allocPrint(allocator, "Hello, {s}. You are {d} years old!", .{ input.name, input.age }) catch unreachable;

    plugin.output(out);
    return 0;
}

export fn json_input_opt() i32 {
    const plugin = Plugin.init(allocator);
    const json = plugin.getJsonOpt(Input, .{ .ignore_unknown_fields = false }) catch |err| {
        switch (err) {
            error.UnknownField => {
                plugin.setError("JSON input contains unknown fields");
                return 1;
            },
            error.DuplicateField => {
                plugin.setError("JSON input contains duplicate fields");
                return 1;
            },
            else => {
                plugin.setError("some problem parsing JSON");
                return 1;
            },
        }
    };
    defer json.deinit();

    const input: Input = json.value();
    const out = std.fmt.allocPrint(allocator, "Hello, {s}. You are {d} years old!\n", .{ input.name, input.age }) catch unreachable;

    plugin.output(out);
    return 0;
}

const Result = struct {
    things: [3][]const u8,
};

export fn json_output() i32 {
    const plugin = Plugin.init(allocator);
    const data = [_][]const u8{
        "first thing",
        "second thing",
        "third thing",
    };

    const result = Result{ .things = data };

    plugin.outputJson(result, .{}) catch unreachable;

    return 0;
}

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

    // get the bytes for the res body
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

    const t = todo.value;
    const tmpl = "[id={d}] '{s}' by user={d} is complete: {any}\n";
    const args = .{ t.id, t.title, t.userId, t.completed };
    const output = std.fmt.allocPrint(allocator, tmpl, args) catch unreachable;
    const outMem = plugin.allocateBytes(output);

    // `outputMemory` provides a zero-copy way to write plugin data back to the host
    plugin.outputMemory(outMem);

    return 0;
}

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

export fn log_stuff() i32 {
    const plugin = Plugin.init(allocator);
    plugin.log(.Info, "An info log!");
    plugin.log(.Debug, "A debug log!");
    plugin.log(.Warn, "A warning log!");
    plugin.log(.Error, "An error log!");

    return 0;
}

const Inner = struct {
    name: []const u8,
    size: usize,
};

const Outer = struct {
    inner: []Inner,
    id: i32,
};

const InnerCount = struct {
    innerCount: u8,
};

export fn nested_json() i32 {
    const plugin = Plugin.init(allocator);

    // get some JSON input, deserialized into InnerCount struct
    const input = plugin.getJson(InnerCount) catch unreachable;

    // create an instance of our Inner struct
    const inner = Inner{
        .name = "I'm the inner struct",
        .size = @sizeOf(Inner),
    };

    // create the list of Inner to be used in the Outer struct
    var innerForOuter = std.ArrayList(Inner).init(allocator);
    defer innerForOuter.deinit();
    // add Inner in the amount specified by the input
    for (0..input.innerCount) |_| {
        innerForOuter.append(inner) catch unreachable;
    }

    // create the Outer struct
    const outer = Outer{
        .inner = innerForOuter.items,
        .id = 42,
    };

    // write the output using the Outer struct serialized to JSON
    plugin.outputJson(outer, .{}) catch unreachable;
    return 0;
}
