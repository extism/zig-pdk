const std = @import("std");
const Memory = @import("memory.zig").Memory;

pub const HttpResponse = struct {
    memory: Memory,
    status: u16,

    /// IMPORTANT: it's the caller's responsibility to free the returned string
    pub fn body(self: HttpResponse, allocator: std.mem.Allocator) ![]u8 {
        var buf = try allocator.alloc(u8, @intCast(usize, self.memory.length));
        errdefer allocator.free(buf);
        self.memory.load(buf);
        return buf;
    }

    pub fn deinit(self: HttpResponse) void {
        self.memory.free();
    }

    pub fn status(self: HttpResponse) u16 {
        return self.status;
    }
};

pub const HttpRequest = struct {
    url: []const u8,
    method: []const u8,
    body: []u8,
    headers: Headers,

    pub fn init(allocator: std.mem.Allocator, method: []const u8, url: []const u8) HttpRequest {
        return HttpRequest{
            .method = method,
            .url = url,
            .headers = Headers.init(allocator),
            .body = "",
        };
    }

    pub fn deinit(self: *HttpRequest) void {
        self.headers.deinit();
    }

    pub fn setHeader(self: *HttpRequest, key: []const u8, value: []const u8) !void {
        try self.headers.append(key, value);
    }

    pub fn setBody(self: *HttpRequest, body: []const u8) void {
        self.body = body;
    }
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Headers = struct {
    allocator: std.mem.Allocator,
    _items: std.ArrayList(Header),
    pub fn init(allocator: std.mem.Allocator) Headers {
        return Headers{ .allocator = allocator, ._items = std.ArrayList(Header).init(allocator) };
    }

    pub fn deinit(self: *Headers) void {
        self._items.deinit();
    }

    pub fn append(self: *Headers, name: []const u8, value: []const u8) !void {
        try self._items.append(Header{ .name = name, .value = value });
    }
};

pub const ExtismHttpRequest = struct {
    headers: []const u8,
    url: []const u8,
    method: []const u8,
};
