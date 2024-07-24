const std = @import("std");
const extism = @import("ffi.zig");
pub const http = @import("http.zig");

const LogLevel = extism.ExtismLogLevel;

var vars: ?std.StringHashMap([]u8) = null;

fn makeHandle(data: []const u8) extism.ExtismHandle {
    const ptr: u64 = @intFromPtr(data.ptr);
    const len: u64 = @intCast(data.len);
    return (ptr << 32) | (len & 0xffffffff);
}

fn makeWriteHandle(data: []u8) extism.ExtismHandle {
    const ptr: u64 = @intFromPtr(data.ptr);
    const len: u64 = @intCast(data.len);
    return (ptr << 32) | (len & 0xffffffff);
}

pub fn Json(comptime T: type) type {
    return struct {
        parsed: std.json.Parsed(T),
        slice: std.ArrayList(u8),

        pub fn value(self: @This()) T {
            return self.parsed.value;
        }

        pub fn deinit(self: @This()) void {
            self.parsed.deinit();
            self.slice.deinit();
        }
    };
}

pub const Plugin = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Plugin {
        return Plugin{
            .allocator = allocator,
        };
    }

    // IMPORTANT: It's the caller's responsibility to free the returned slice
    pub fn getInput(self: Plugin) !std.ArrayList(u8) {
        var buf: [1024]u8 = undefined;
        var dest = std.ArrayList(u8).init(self.allocator);
        var n: i64 = 0;
        while (n >= 0) {
            n = extism.read(extism.ExtismStream.Input, makeWriteHandle(&buf));
            if (n > 0) {
                try dest.appendSlice(buf[0..@intCast(n)]);
            }
        }
        return dest;
    }

    // IMPORTANT: It's the caller's responsibility to free the returned struct
    pub fn getJsonOpt(self: Plugin, comptime T: type, options: std.json.ParseOptions) !Json(T) {
        const bytes = try self.getInput();
        const out = try std.json.parseFromSlice(T, self.allocator, bytes.items, options);
        const FromJson = Json(T);
        const input = FromJson{ .parsed = out, .slice = bytes };
        return input;
    }

    pub fn getJson(self: Plugin, comptime T: type) !T {
        const bytes = try self.getInput();
        defer bytes.deinit();
        const out = try std.json.parseFromSlice(T, self.allocator, bytes.items, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
        return out.value;
    }

    pub fn output(self: Plugin, data: []const u8) void {
        _ = self; // to make the interface consistent
        _ = extism.write(extism.ExtismStream.Output, makeHandle(data));
        // TODO: handle failed/short write
    }

    pub fn outputJson(self: Plugin, T: anytype, options: std.json.StringifyOptions) !void {
        const out = try std.json.stringifyAlloc(self.allocator, T, options);
        self.output(out);
    }

    pub fn throwError(self: Plugin, data: []const u8) void {
        _ = self; // to make the interface consistent
        extism.@"error"(makeHandle(data));
    }

    pub fn getConfig(self: Plugin, key: []const u8) !?[]u8 {
        const keyHandle = makeHandle(key);
        const length = extism.config_length(keyHandle);
        if (length < 0) {
            return null;
        }

        const data = try self.allocator.alloc(u8, @intCast(length));
        _ = extism.config_read(keyHandle, makeWriteHandle(data));
        return data;
    }

    pub fn log(self: Plugin, level: LogLevel, data: []const u8) void {
        _ = self; // to make the interface consistent
        extism.log(level, makeHandle(data));
    }

    pub fn getVar(self: Plugin, key: []const u8) ?[]u8 {
        _ = self;
        if (vars) |v| {
            return v.get(key);
        } else {
            return null;
        }
    }

    pub fn getVarInt(self: Plugin, comptime T: type, key: []const u8) !?T {
        const result = self.getVar(key);

        if (result) |buf| {
            return std.mem.readPackedInt(T, buf, 0, .little);
        }

        return null;
    }

    pub fn setVar(self: Plugin, key: []const u8, value: []const u8) !void {
        if (vars == null) {
            vars = std.StringHashMap([]u8).init(self.allocator);
        }
        if (vars) |*v| {
            if (v.fetchRemove(key)) |_| {
                // self.allocator.free(x);
            }
            try v.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
        }
    }

    pub fn setVarInt(self: Plugin, comptime T: type, key: []const u8, value: T) !void {
        const buffer = try self.allocator.alloc(u8, @sizeOf(T));
        defer self.allocator.free(buffer);
        std.mem.writePackedInt(T, buffer, 0, value, .little);

        try self.setVar(key, buffer);
    }

    pub fn removeVar(self: Plugin, key: []const u8) void {
        if (vars) |v| {
            if (v.fetchRemove(key)) |x| {
                self.allocator.free(x);
            }
        }
    }

    pub fn request(self: Plugin, http_request: http.HttpRequest, body: ?[]const u8) !http.HttpResponse {
        const json = try std.json.stringifyAlloc(self.allocator, http_request, .{ .emit_null_optional_fields = false });
        defer self.allocator.free(json);
        const req_body = b: {
            if (body) |bdy| {
                break :b makeHandle(bdy);
            } else {
                break :b 0;
            }
        };
        const length = extism.http_request(makeHandle(json), req_body);
        const status: u16 = @intCast(extism.http_status_code());

        return http.HttpResponse{
            .length = @intCast(length),
            .status = status,
        };
    }
};
