const std = @import("std");
const zig_pdk = @import("extism-pdk");
const pdk = zig_pdk.Plugin;
const http = zig_pdk.http;

pub fn main() void {}
const allocator = std.heap.wasm_allocator;

// define some type to write as output from the plugin back to the host
const Output = struct {
    count: i32,
    config: []const u8,
    a: []const u8,
};

export fn count_vowels() i32 {
    const plugin = pdk.init(allocator);
    plugin.log(zig_pdk.LogLevel.Debug, "plugin start");
    const input = plugin.getInput() catch unreachable;
    defer allocator.free(input);
    plugin.log(zig_pdk.LogLevel.Debug, "plugin input");
    var count: i32 = 0;
    for (input) |char| {
        switch (char) {
            'A', 'I', 'E', 'O', 'U', 'a', 'e', 'i', 'o', 'u' => count += 1,
            else => {},
        }
    }

    // use persistent variables owned by a plugin instance (stored in-memory between function calls)
    var var_a_optional = plugin.getVar("a") catch unreachable;
    plugin.log(zig_pdk.LogLevel.Debug, "plugin var get");

    if (var_a_optional == null) {
        plugin.setVar("a", "this is var a");
        plugin.log(zig_pdk.LogLevel.Debug, "plugin var set");
    } else {
        allocator.free(var_a_optional.?);
    }
    const var_a = plugin.getVar("a") catch unreachable orelse "";
    defer allocator.free(var_a);

    // access host-provided configuration (key/value)
    const thing = plugin.getConfig("thing") catch unreachable orelse "<unset by host>";
    plugin.log(zig_pdk.LogLevel.Debug, "plugin config get");

    const data = Output{ .count = count, .config = thing, .a = var_a };
    const output = std.json.stringifyAlloc(allocator, data, .{}) catch unreachable;
    defer allocator.free(output);
    plugin.log(zig_pdk.LogLevel.Debug, "plugin json encoding");

    // write the plugin data back to the host
    plugin.output(output);
    plugin.log(zig_pdk.LogLevel.Debug, "plugin output");

    return 0;
}

export fn make_http_request() i32 {
    const plugin = pdk.init(allocator);
    // create an HTTP request via Extism built-in function (doesn't require WASI)
    var req = http.HttpRequest.init(allocator, "GET", "https://jsonplaceholder.typicode.com/todos/1");
    defer req.deinit();

    // set headers on the request object
    req.setHeader("some-name", "some-value") catch unreachable;
    req.setHeader("another", "again") catch unreachable;

    // make the request and get the response back
    const res = plugin.request(req) catch unreachable;
    defer res.deinit();

    // `outputMemory` provides a zero-copy way to write plugin data back to the host
    plugin.outputMemory(res.memory);

    return 0;
}
