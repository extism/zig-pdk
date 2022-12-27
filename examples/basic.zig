const std = @import("std");
const zig_pdk = @import("extism-pdk");
const pdk = zig_pdk.Plugin;
const http = zig_pdk.http;

pub fn main() void {}
const allocator = std.heap.wasm_allocator;

export fn count_vowels() i32 {
    const plugin = pdk.init(allocator);
    const input = plugin.getInput() catch unreachable;
    defer allocator.free(input);
    var count: i32 = 0;
    for (input) |char| {
        switch (char) {
            'A', 'I', 'E', 'O', 'U', 'a', 'e', 'i', 'o', 'u' => count += 1,
            else => {},
        }
    }
    var var_a_optional = plugin.getVar("a") catch unreachable;
    if (var_a_optional == null) {
        plugin.setVar("a", "this is var a");
    } else {
        allocator.free(var_a_optional.?);
    }
    const var_a = plugin.getVar("a") catch unreachable orelse "";
    defer allocator.free(var_a);

    const thing = plugin.getConfig("thing") catch unreachable orelse "<unset by host>";

    const output = std.fmt.allocPrint(allocator, "{{\"count\": {d}, \"config\": \"{s}\", \"a\": \"{s}\"}}", .{ count, thing, var_a }) catch unreachable;
    defer allocator.free(output);

    plugin.output(output);

    return 0;
}

export fn make_http_request() i32 {
    const plugin = pdk.init(allocator);
    var req = http.HttpRequest.init(allocator, "GET", "https://jsonplaceholder.typicode.com/todos/1");
    req.setHeader("some-name", "some-value") catch unreachable;
    req.setHeader("another", "again") catch unreachable;

    defer req.deinit();
    const res = plugin.request(req) catch unreachable;
    defer res.deinit();

    plugin.outputMemory(res.memory);

    return 0;
}
