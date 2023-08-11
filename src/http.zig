const std = @import("std");
const Memory = @import("Memory.zig");

pub const HttpResponse = struct {
    memory: Memory,
    status: u16,

    /// IMPORTANT: it's the caller's responsibility to free the returned string
    pub fn body(self: HttpResponse, allocator: std.mem.Allocator) ![]u8 {
        var buf = try allocator.alloc(u8, @intCast(self.memory.length));
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
    headers: std.json.ArrayHashMap([]const u8),

    pub fn init(method: []const u8, url: []const u8) HttpRequest {
        return HttpRequest{
            .method = method,
            .url = url,
            .headers = std.json.ArrayHashMap([]const u8){},
        };
    }

    pub fn deinit(self: *HttpRequest, allocator: std.mem.Allocator) void {
        self.headers.deinit(allocator);
    }

    pub fn setHeader(self: *HttpRequest, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        try self.headers.map.put(allocator, key, value);
    }
};
