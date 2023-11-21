const std = @import("std");
const extism = @import("ffi.zig");

const Self = @This();

offset: u64,
length: u64,

pub fn init(offset: u64, length: u64) Self {
    return .{
        .offset = offset,
        .length = length,
    };
}

pub fn load(self: Self, buf: []u8) void {
    const len = buf.len;

    var i: usize = 0;
    while (i < len) {
        if (len - i < 8) {
            buf[i] = extism.load_u8(self.offset + @as(u64, i));
            i += 1;
            continue;
        }

        const x = extism.load_u64(self.offset + @as(u64, i));
        std.mem.writeInt(u64, buf[i..][0..8], x, std.builtin.Endian.Little);
        i += 8;
    }
}

pub fn store(self: Self, buf: []const u8) void {
    const len = buf.len;
    var i: usize = 0;
    while (i < len) {
        if (len - i < 8) {
            extism.store_u8(self.offset + @as(u64, i), buf[i]);
            i += 1;
            continue;
        }
        const data = std.mem.readInt(u64, buf[i..][0..8], std.builtin.Endian.Little);
        extism.store_u64(self.offset + @as(u64, i), data);
        i += 8;
    }
}

pub fn allocate(length: usize) Self {
    const c_len = @as(u64, length);
    const offset = extism.alloc(c_len);

    return .{ .offset = @as(u64, offset), .length = @as(u64, c_len) };
}

pub fn allocateBytes(data: []const u8) Self {
    const c_len = @as(u64, data.len);
    const offset = extism.alloc(c_len);
    const mem = init(offset, c_len);
    mem.store(data);
    return .{ .offset = offset, .length = c_len };
}

pub fn free(self: Self) void {
    extism.free(self.offset);
}
