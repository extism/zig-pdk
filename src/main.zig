const std = @import("std");
const c = @import("ffi.zig");
const tres = @import("tres");
const Memory = @import("memory.zig").Memory;
pub const http = @import("http.zig");

const LogLevel = enum { Info, Debug, Warn, Error };

pub const Plugin = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Plugin {
        return Plugin{
            .allocator = allocator,
        };
    }

    // IMPORTANT: It's the caller's responsibility to free the returned slice
    pub fn getInput(self: Plugin) ![]u8 {
        const len = c.extism_input_length();
        var buf = try self.allocator.alloc(u8, @intCast(usize, len));
        errdefer self.allocator.free(buf);
        var i: usize = 0;
        while (i < len) {
            if (len - i < 8) {
                buf[i] = c.extism_input_load_u8(@as(u64, i));
                i += 1;
                continue;
            }

            const x = c.extism_input_load_u64(@as(u64, i));
            std.mem.writeIntLittle(u64, buf[i..][0..8], x);
            i += 8;
        }
        return buf;
    }

    pub fn outputMemory(self: Plugin, mem: Memory) void {
        _ = self; // to make the interface consistent
        c.extism_output_set(mem.offset, mem.length);
    }

    pub fn output(self: Plugin, data: []const u8) void {
        _ = self; // to make the interface consistent
        const c_len = @as(u64, data.len);
        const offset = c.extism_alloc(c_len);
        const memory = Memory.init(offset, c_len);
        defer memory.free();
        memory.store(data);
        c.extism_output_set(offset, c_len);
    }

    /// IMPORTANT: it's the caller's responsibility to free the returned string
    pub fn getConfig(self: Plugin, key: []const u8) !?[]u8 {
        const key_mem = Memory.allocateBytes(key);
        defer key_mem.free();
        const offset = c.extism_config_get(key_mem.offset);
        const c_len = c.extism_length(offset);
        if (offset == 0 or c_len == 0) {
            return null;
        }
        const memory = Memory.init(offset, c_len);
        defer memory.free();
        const value = try self.allocator.alloc(u8, @intCast(usize, c_len));
        errdefer self.allocator.free(value);
        memory.load(value);
        return value;
    }

    /// There's an unresolved 'Invalid memory offset' error when calling this function directly.
    /// Use `log` instead.
    pub fn logMemory(self: Plugin, level: LogLevel, memory: Memory) void {
        _ = self; // to make the interface consistent
        switch (level) {
            .Info => c.extism_log_info(memory.offset),
            .Debug => c.extism_log_debug(memory.offset),
            .Warn => c.extism_log_warn(memory.offset),
            .Error => c.extism_log_error(memory.offset),
        }
    }

    pub fn log(self: Plugin, level: LogLevel, data: []const u8) void {
        const mem = Memory.allocateBytes(data);
        defer mem.free();
        self.logMemory(level, mem);
    }

    /// IMPORTANT: it's the caller's responsibility to free the returned string
    pub fn getVar(self: Plugin, key: []const u8) !?[]u8 {
        const key_mem = Memory.allocateBytes(key);
        defer key_mem.free();
        const offset = c.extism_var_get(key_mem.offset);
        const c_len = c.extism_length(offset);
        if (offset == 0 or c_len == 0) {
            return null;
        }
        const memory = Memory.init(offset, c_len);
        defer memory.free();
        const value = try self.allocator.alloc(u8, @intCast(usize, c_len));
        errdefer self.allocator.free(value);
        memory.load(value);
        return value;
    }

    pub fn setVar(self: Plugin, key: []const u8, value: []const u8) void {
        _ = self; // to make the interface consistent
        const key_mem = Memory.allocateBytes(key);
        defer key_mem.free();
        const val_mem = Memory.allocateBytes(value);
        defer val_mem.free();
        c.extism_var_set(key_mem.offset, val_mem.offset);
    }

    pub fn removeVar(self: Plugin, key: []const u8) void {
        _ = self; // to make the interface consistent
        const mem = Memory.allocateBytes(key);
        defer mem.free();
        c.extism_var_set(mem.offset, 0);
    }

    pub fn request(self: Plugin, http_request: http.HttpRequest, body: ?[]const u8) !http.HttpResponse {
        var json_arraylist = std.ArrayList(u8).init(self.allocator);
        var json_writer = std.io.bufferedWriter(json_arraylist.writer());
        try tres.stringify(http_request, .{}, json_writer.writer());
        try json_writer.flush();
        const json_str = try json_arraylist.toOwnedSlice();
        defer self.allocator.free(json_str);
        const req = Memory.allocateBytes(json_str);
        defer req.free();
        const req_body = b: {
            if (body) |bdy| {
                break :b Memory.allocateBytes(bdy);
            } else {
                break :b Memory.allocate(0);
            }
        };
        defer req_body.free();
        const offset = c.extism_http_request(req.offset, req_body.offset);
        const length = c.extism_length(offset);
        const status = @intCast(u16, c.extism_http_status_code());

        const mem = Memory.init(offset, length);
        defer mem.free();
        return http.HttpResponse{
            .memory = mem,
            .status = status,
        };
    }
};
