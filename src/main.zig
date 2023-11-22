const std = @import("std");
const extism = @import("ffi.zig");
const Memory = @import("Memory.zig");
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
        const len = extism.input_length();
        var buf = try self.allocator.alloc(u8, @intCast(len));
        errdefer self.allocator.free(buf);
        var i: usize = 0;
        while (i < len) {
            if (len - i < 8) {
                buf[i] = extism.input_load_u8(@as(u64, i));
                i += 1;
                continue;
            }

            const x = extism.input_load_u64(@as(u64, i));
            std.mem.writeInt(u64, buf[i..][0..8], x, std.builtin.Endian.little);
            i += 8;
        }
        return buf;
    }

    pub fn outputMemory(self: Plugin, mem: Memory) void {
        _ = self; // to make the interface consistent
        extism.output_set(mem.offset, mem.length);
    }

    pub fn output(self: Plugin, data: []const u8) void {
        _ = self; // to make the interface consistent
        const c_len = @as(u64, data.len);
        const offset = extism.alloc(c_len);
        const memory = Memory.init(offset, c_len);
        defer memory.free();
        memory.store(data);
        extism.output_set(offset, c_len);
    }

    pub fn setErrorMemory(self: Plugin, mem: Memory) void {
        _ = self; // to make the interface consistent
        extism.error_set(mem.offset);
    }

    pub fn setError(self: Plugin, data: []const u8) void {
        _ = self; // to make the interface consistent
        const c_len = @as(u64, data.len);
        const offset = extism.alloc(c_len);
        const memory = Memory.init(offset, c_len);
        defer memory.free();
        memory.store(data);
        extism.error_set(offset);
    }

    /// IMPORTANT: it's the caller's responsibility to free the returned string
    pub fn getConfig(self: Plugin, key: []const u8) !?[]u8 {
        const key_mem = Memory.allocateBytes(key);
        defer key_mem.free();
        const offset = extism.config_get(key_mem.offset);
        const c_len = extism.length(offset);
        if (offset == 0 or c_len == 0) {
            return null;
        }
        const memory = Memory.init(offset, c_len);
        defer memory.free();
        const value = try self.allocator.alloc(u8, @intCast(c_len));
        errdefer self.allocator.free(value);
        memory.load(value);
        return value;
    }

    pub fn logMemory(self: Plugin, level: LogLevel, memory: Memory) void {
        _ = self; // to make the interface consistent
        switch (level) {
            .Info => extism.log_info(memory.offset),
            .Debug => extism.log_debug(memory.offset),
            .Warn => extism.log_warn(memory.offset),
            .Error => extism.log_error(memory.offset),
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
        const offset = extism.var_get(key_mem.offset);
        const c_len = extism.length(offset);
        if (offset == 0 or c_len == 0) {
            return null;
        }
        const memory = Memory.init(offset, c_len);
        defer memory.free();
        const value = try self.allocator.alloc(u8, @intCast(c_len));
        errdefer self.allocator.free(value);
        memory.load(value);
        return value;
    }

    pub fn getVarInt(self: Plugin, comptime T: type, key: []const u8) !?T {
        const result = try self.getVar(key);

        if (result) |buf| {
            return std.mem.readPackedInt(i32, buf, 0, .little);
        }

        return null;
    }

        defer key_mem.free();
        const val_mem = Memory.allocateBytes(value);
        defer val_mem.free();
        extism.var_set(key_mem.offset, val_mem.offset);
    }

    pub fn setVarInt(self: Plugin, comptime T: type, key: []const u8, value: T) !void {
        const buffer = try self.allocator.alloc(u8, 8);
        errdefer self.allocator.free(buffer);
        std.mem.writePackedInt(T, buffer, 0, value, .little);

        self.setVar(key, buffer);
    }

        defer mem.free();
        extism.extism_var_set(mem.offset, 0);
    }

    pub fn request(self: Plugin, http_request: http.HttpRequest, body: ?[]const u8) !http.HttpResponse {
        const json = try std.json.stringifyAlloc(self.allocator, http_request, .{ .emit_null_optional_fields = false });
        defer self.allocator.free(json);
        const req = Memory.allocateBytes(json);
        defer req.free();
        const req_body = b: {
            if (body) |bdy| {
                break :b Memory.allocateBytes(bdy);
            } else {
                break :b Memory.allocate(0);
            }
        };
        defer req_body.free();
        const offset = extism.http_request(req.offset, req_body.offset);
        const length = extism.length(offset);
        const status: u16 = @intCast(extism.http_status_code());

        const mem = Memory.init(offset, length);
        defer mem.free();
        return http.HttpResponse{
            .memory = mem,
            .status = status,
        };
    }
};
