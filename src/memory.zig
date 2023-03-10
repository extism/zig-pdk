const std = @import("std");
const c = @import("ffi.zig");

pub const Memory = struct {
    offset: u64,
    length: u64,

    pub fn init(offset: u64, length: u64) Memory {
        return Memory{
            .offset = offset,
            .length = length,
        };
    }

    pub fn load(self: Memory, buf: []u8) void {
        const len = buf.len;

        var i: usize = 0;
        while (i < len) {
            if (len - i < 8) {
                buf[i] = c.extism_load_u8(self.offset + @as(u64, i));
                i += 1;
                continue;
            }

            const x = c.extism_load_u64(self.offset + @as(u64, i));
            std.mem.writeIntLittle(u64, buf[i..][0..8], x);
            i += 8;
        }
    }

    pub fn store(self: Memory, buf: []const u8) void {
        const len = buf.len;
        var i: usize = 0;
        while (i < len) {
            if (len - i < 8) {
                c.extism_store_u8(self.offset + @as(u64, i), buf[i]);
                i += 1;
                continue;
            }
            const data = std.mem.readIntLittle(u64, buf[i..][0..8]);
            c.extism_store_u64(self.offset + @as(u64, i), data);
            i += 8;
        }
    }

    pub fn allocate(length: usize) Memory {
        const c_len = @as(u64, length);
        const offset = c.extism_alloc(c_len);

        return Memory{ .offset = @as(u64, offset), .length = @as(u64, c_len) };
    }

    pub fn allocateBytes(data: []const u8) Memory {
        const c_len = @as(u64, data.len);
        const offset = c.extism_alloc(c_len);
        const mem = Memory.init(offset, c_len);
        mem.store(data);
        return Memory{ .offset = offset, .length = c_len };
    }

    pub fn free(self: Memory) void {
        c.extism_free(self.offset);
    }
};
