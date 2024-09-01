/// Md5 Implementation following the Pseudocode on https://en.wikipedia.org/wiki/MD5
const std = @import("std");
const FixedBufferAllocator = @import("std").heap.FixedBufferAllocator;
const time = @import("std").time;

const init_a: u32 = 0x67452301;
const init_b: u32 = 0xefcdab89;
const init_c: u32 = 0x98badcfe;
const init_d: u32 = 0x10325476;

const s_table: [64]u5 = init: {
    const shift_table = .{
        [_]u5{ 7, 12, 17, 22 }, //
        [_]u5{ 5, 9, 14, 20 }, //
        [_]u5{ 4, 11, 16, 23 }, //
        [_]u5{ 6, 10, 15, 21 }, //
    };

    var result: [64]u5 = undefined;
    for (0..4) |table_index| {
        for (table_index * 16..(table_index + 1) * 16) |i| {
            result[i] = shift_table[table_index][i % 4];
        }
    }
    break :init result;
};

const k_table = init: {
    var result: [64]u32 = undefined;
    for (&result, 0..) |*p, i| {
        p.* = @as(u32, @floor((1 << 32) * @abs(@sin(@as(f64, i) + 1))));
    }
    break :init result;
};

/// Computes the md5 hash using optimizations for short (length 0-13) inputs.
pub fn computeMd5_shortU32(message: []const u32, hash: *[4]u32) !void {
    if (message.len > 13) return error.MessageTooLong;

    var block: [16]u32 = undefined;
    @memcpy(block[0..message.len], message);
    block[message.len] = 0x80;
    for (message.len + 1..16) |i| {
        block[i] = 0;
    }
    block[14] = @truncate(message.len * 32);

    var a = init_a;
    var b = init_b;
    var c = init_c;
    var d = init_d;

    inline for (0..4) |round| {
        inline for (round * 16..(round + 1) * 16) |i| {
            const g = comptime switch (round) {
                0 => i,
                1 => ((5 * i) + 1) & 0x0f,
                2 => ((3 * i) + 5) & 0x0f,
                3 => (7 * i) & 0x0f,
                else => unreachable,
            };
            const f = switch (round) {
                inline 0 => ((b & c) | (~b & d)),
                inline 1 => ((d & b) | (~d & c)),
                inline 2 => (b ^ c ^ d),
                inline 3 => (c ^ (b | ~d)),
                else => unreachable,
            } +% block[g] +% a +% k_table[i];

            a = d;
            d = c;
            c = b;
            const shift: u5 = s_table[i];
            b = b +% ((f << shift) | (f >> (~shift +% 1)));
        }
    }

    hash[0] = init_a +% a;
    hash[1] = init_b +% b;
    hash[2] = init_c +% c;
    hash[3] = init_d +% d;
}

export fn c_computeMd5(message: [*c]const u8, len: usize, hash: *[4]u32) void {
    computeMd5(message[0..len], hash);
}

pub fn computeMd5(message: []const u8, hash: *[4]u32) void {
    const num_extra: u8 = @truncate(message.len % 64);
    const num_msg_blocks = message.len / 64;
    var pad_len: usize = undefined;
    if (num_extra >= 56) {
        pad_len = 32;
    } else {
        pad_len = 16;
    }
    var pad_block = [_]u32{0} ** 32;
    for (0..num_extra) |i| {
        pad_block[i / 4] |= (@as(u32, message[message.len - num_extra + i]) << (@as(u5, @truncate(i % 4)) * 8));
    }
    pad_block[num_extra / 4] |= @as(u32, 0x80) << (@as(u5, @truncate(num_extra % 4)) * 8);

    // Die letzten 8 bytes mit der urspruenglichen Laenge der Nachricht befuellen
    const original_length_bits: u64 = message.len * 8;
    pad_block[pad_len - 2] = @truncate(original_length_bits & 0xffffffff);
    pad_block[pad_len - 1] = @truncate((original_length_bits >> 32) & 0xffffffff);

    hash[0] = init_a;
    hash[1] = init_b;
    hash[2] = init_c;
    hash[3] = init_d;

    for (0..num_msg_blocks) |block_index| {
        const buffer: [*]const u32 = @ptrCast(@alignCast(message[(block_index * 64)..((block_index + 1) * 64)]));
        var a = hash[0];
        var b = hash[1];
        var c = hash[2];
        var d = hash[3];

        inline for (0..4) |round| {
            inline for (round * 16..(round + 1) * 16) |i| {
                const g = comptime switch (round) {
                    0 => undefined,
                    1 => ((5 * i) + 1) & 0x0f,
                    2 => ((3 * i) + 5) & 0x0f,
                    3 => (7 * i) & 0x0f,
                    else => unreachable,
                };
                const f = switch (round) {
                    inline 0 => ((b & c) | (~b & d)) +% buffer[i],
                    inline 1 => ((d & b) | (~d & c)) +% buffer[g],
                    inline 2 => (b ^ c ^ d) +% buffer[g],
                    inline 3 => (c ^ (b | ~d)) +% buffer[g],
                    else => unreachable,
                } +% a +% k_table[i];

                a = d;
                d = c;
                c = b;
                const shift: u5 = s_table[i];
                b = b +% ((f << shift) | (f >> (~shift +% 1)));
            }
        }

        hash[0] +%= a;
        hash[1] +%= b;
        hash[2] +%= c;
        hash[3] +%= d;
    }

    const num_padding_blocks = pad_len / 16;
    for (0..num_padding_blocks) |pad_index| {
        // Letze Runde auf dem Padding drehen
        const pad_block_i = 16 * pad_index;
        var a = hash[0];
        var b = hash[1];
        var c = hash[2];
        var d = hash[3];

        inline for (0..4) |round| {
            inline for (round * 16..(round + 1) * 16) |i| {
                const g = comptime switch (round) {
                    0 => undefined,
                    1 => ((5 * i) + 1) & 0x0f,
                    2 => ((3 * i) + 5) & 0x0f,
                    3 => (7 * i) & 0x0f,
                    else => unreachable,
                };
                const f = switch (round) {
                    inline 0 => ((b & c) | (~b & d)) +% pad_block[i + pad_block_i],
                    inline 1 => ((d & b) | (~d & c)) +% pad_block[g + pad_block_i],
                    inline 2 => (b ^ c ^ d) +% pad_block[g + pad_block_i],
                    inline 3 => (c ^ (b | ~d)) +% pad_block[g + pad_block_i],
                    else => unreachable,
                } +% a +% k_table[i];

                a = d;
                d = c;
                c = b;
                const shift: u5 = s_table[i];
                b = b +% ((f << shift) | (f >> (~shift +% 1)));
            }
        }

        hash[0] +%= a;
        hash[1] +%= b;
        hash[2] +%= c;
        hash[3] +%= d;
    }
}

pub fn toHexString(hash: *[4]u32, result: *[32]u8) !void {
    _ = try std.fmt.bufPrint(
        result,
        "{x:0>8}{x:0>8}{x:0>8}{x:0>8}",
        .{ @byteSwap(hash[0]), @byteSwap(hash[1]), @byteSwap(hash[2]), @byteSwap(hash[3]) },
    );
}

test "message of 1016 bytes : matches precomputed hash" {
    const message = [_]u8{ 0xff, 0xdd, 0x2b, 0x9b, 0x7f, 0x45, 0xde, 0x3a, 0xac, 0x32, 0xf1, 0x92, 0xb8, 0x0b, 0xb2, 0xc7, 0x7e, 0xca, 0x53, 0x05, 0x65, 0x01, 0x1b, 0x5f, 0x93, 0x34, 0xcb, 0x6e, 0x1f, 0xb1, 0xde, 0xdd, 0xb1, 0xf4, 0x77, 0x93, 0x46, 0xd6, 0xea, 0x65, 0x8f, 0x0a, 0x15, 0xde, 0x9b, 0x76, 0x1a, 0xef, 0xd7, 0x2a, 0x1d, 0xc9, 0x59, 0x77, 0xe9, 0x61, 0xae, 0x40, 0xf5, 0x06, 0xe7, 0x90, 0x2b, 0xf7, 0xc9, 0xdf, 0xf6, 0xed, 0x97, 0x5c, 0x37, 0xb8, 0x58, 0xe2, 0x99, 0xd3, 0x19, 0x6a, 0x14, 0xef, 0x4c, 0x53, 0xfd, 0xe6, 0x7e, 0x66, 0x94, 0x7c, 0xc4, 0x4c, 0x62, 0x09, 0x06, 0x75, 0xe6, 0xd7, 0xa6, 0x6b, 0x4d, 0xd4, 0x12, 0x7a, 0x9a, 0xb3, 0xad, 0x34, 0xaf, 0x6f, 0xe5, 0x52, 0x64, 0x80, 0x73, 0x14, 0x34, 0xd0, 0x24, 0x59, 0x37, 0x25, 0x44, 0xd3, 0xc0, 0x3c, 0x32, 0x2f, 0xee, 0x84, 0xb8, 0x36, 0x90, 0xaf, 0xd6, 0x3a, 0xb5, 0x55, 0x68, 0x6e, 0x16, 0xe9, 0xd4, 0x75, 0x7d, 0xcb, 0x38, 0x9e, 0xd3, 0x12, 0x5d, 0xe8, 0x95, 0xd2, 0x13, 0xb0, 0x41, 0x41, 0x81, 0x47, 0x23, 0x32, 0x06, 0x60, 0x9c, 0x52, 0x08, 0x62, 0x7c, 0xaa, 0x17, 0x81, 0x53, 0xf6, 0x61, 0x50, 0xcf, 0x8f, 0x5b, 0x96, 0x65, 0x90, 0x82, 0x50, 0x9d, 0x50, 0x0b, 0x5b, 0x2f, 0xdd, 0xf1, 0xe4, 0x5a, 0xab, 0xa9, 0x85, 0x67, 0x3c, 0x53, 0xc6, 0xee, 0x84, 0x7f, 0x45, 0x6d, 0x90, 0x2a, 0x89, 0x2e, 0xb6, 0xf0, 0x7e, 0xac, 0xd2, 0xac, 0x15, 0xd4, 0x16, 0x76, 0xf2, 0x41, 0xbe, 0xe1, 0x45, 0x96, 0xd4, 0x4f, 0x13, 0xe1, 0x1b, 0x63, 0xbe, 0x8a, 0x70, 0x15, 0xae, 0x67, 0x47, 0x70, 0x70, 0x3b, 0xa0, 0xdd, 0x6c, 0xbb, 0x67, 0x3b, 0xb8, 0x69, 0x0a, 0x97, 0x15, 0x7a, 0x9c, 0x96, 0xc8, 0x80, 0x8f, 0xb9, 0xe0, 0x3e, 0x98, 0x69, 0x9d, 0x54, 0xee, 0x83, 0xc9, 0xe1, 0xd7, 0x9b, 0x10, 0xe8, 0x20, 0x5f, 0x0e, 0xde, 0x5b, 0x53, 0x79, 0xd8, 0xd9, 0x21, 0x8f, 0x8c, 0xba, 0xb7, 0x83, 0x76, 0x52, 0x3d, 0x20, 0xcf, 0x21, 0x9a, 0x3f, 0x80, 0xd8, 0x29, 0x95, 0x81, 0x74, 0xb4, 0xce, 0x7f, 0xac, 0x85, 0x01, 0x0b, 0x7d, 0x5a, 0x2f, 0x4b, 0x2c, 0xbe, 0xcf, 0x28, 0x77, 0xd2, 0x6e, 0x95, 0x43, 0x44, 0x9d, 0xa9, 0x38, 0xb0, 0xa6, 0x0f, 0x58, 0x9a, 0x9f, 0x17, 0x21, 0xea, 0x9a, 0xd2, 0xf8, 0xb3, 0x7a, 0xda, 0x10, 0x7c, 0x2a, 0x39, 0x33, 0x89, 0x38, 0xa4, 0x01, 0xd5, 0x1a, 0x9b, 0xb8, 0xcd, 0x4a, 0xda, 0x27, 0x67, 0xa6, 0xf8, 0x2f, 0x1b, 0x7b, 0xa4, 0x90, 0x0e, 0xb1, 0x65, 0xf8, 0x21, 0x3b, 0x3b, 0x0b, 0x27, 0x29, 0xea, 0xc8, 0x94, 0x35, 0xd4, 0x4b, 0x95, 0xfa, 0x90, 0x92, 0xe9, 0x21, 0xdf, 0xac, 0x01, 0xa1, 0xa3, 0x41, 0x27, 0x00, 0xaa, 0x32, 0x16, 0xe9, 0xcb, 0xd5, 0x5a, 0xd7, 0x5f, 0xa1, 0x8f, 0x5c, 0xd4, 0x2a, 0x63, 0x28, 0x21, 0x02, 0x4a, 0x3b, 0x89, 0x0a, 0x3d, 0x50, 0x93, 0x64, 0xc3, 0x53, 0xd5, 0x16, 0xed, 0x5f, 0x72, 0x7f, 0x9d, 0x97, 0x87, 0x56, 0xbe, 0x4d, 0x9e, 0x49, 0x2b, 0x7d, 0x06, 0x8b, 0x6f, 0x22, 0x1c, 0xaa, 0x11, 0x2d, 0xee, 0x2a, 0x83, 0xb6, 0xe1, 0x1f, 0x76, 0xb3, 0x55, 0xed, 0xd0, 0x06, 0x37, 0x1e, 0x61, 0xfe, 0x17, 0xd7, 0x00, 0xed, 0x3b, 0xd6, 0x36, 0xef, 0x0f, 0x28, 0xa5, 0x6f, 0x21, 0x07, 0x69, 0x3b, 0x26, 0x5f, 0x09, 0xb7, 0xd8, 0x73, 0xe7, 0xd8, 0xe5, 0x38, 0xe6, 0x4e, 0x51, 0x33, 0xc4, 0x4c, 0x14, 0xe4, 0xa8, 0x8a, 0x5f, 0x5e, 0x2f, 0xf7, 0x18, 0x57, 0xe4, 0xf0, 0xd1, 0x8b, 0xb7, 0x75, 0x8e, 0x39, 0x30, 0x54, 0xf9, 0xf1, 0x67, 0xfd, 0x56, 0xd0, 0x7a, 0x02, 0xdf, 0xff, 0x4d, 0x30, 0x76, 0x4e, 0x91, 0x09, 0xa4, 0x15, 0x59, 0xfe, 0x1c, 0xf0, 0x83, 0x46, 0x6d, 0xee, 0xc2, 0xa7, 0x0d, 0xce, 0xee, 0x9e, 0xdb, 0x76, 0x4b, 0x87, 0xd4, 0x02, 0x8b, 0xae, 0x84, 0xff, 0x24, 0xf5, 0x75, 0x7b, 0x6c, 0x30, 0x05, 0x08, 0x3c, 0xe7, 0x78, 0xd8, 0xc8, 0xca, 0x56, 0xed, 0x37, 0x02, 0xc2, 0xc5, 0x4d, 0x75, 0x82, 0xe6, 0x6d, 0x26, 0xb3, 0xa2, 0x4a, 0xc5, 0x37, 0xdc, 0x99, 0x36, 0x9a, 0x9a, 0x3c, 0xd0, 0x20, 0xed, 0x22, 0x72, 0x3f, 0xfc, 0x71, 0x5c, 0x4f, 0xf0, 0x26, 0x53, 0x8b, 0x9e, 0xe9, 0x90, 0xf8, 0x7e, 0xa9, 0x00, 0x57, 0xab, 0xa0, 0x90, 0x3a, 0xe3, 0x9d, 0x1f, 0xdd, 0x5e, 0xd8, 0x3a, 0x06, 0xeb, 0x9b, 0xb1, 0x05, 0xe3, 0x2f, 0xf9, 0x2d, 0x7a, 0x83, 0xce, 0x73, 0x5f, 0x76, 0xe5, 0x10, 0xa3, 0x61, 0xee, 0x02, 0x88, 0xa6, 0xf4, 0xb3, 0x21, 0x47, 0x3b, 0x09, 0xd2, 0x6d, 0x09, 0x0e, 0x2e, 0xf9, 0x8e, 0x19, 0x31, 0x27, 0x28, 0x21, 0x4e, 0xa6, 0x66, 0x39, 0x69, 0x38, 0x4f, 0x64, 0xa0, 0xfa, 0xc6, 0xa2, 0x29, 0x2a, 0x02, 0x8d, 0xf2, 0x50, 0xd5, 0xaf, 0xdb, 0xf9, 0x32, 0x74, 0xb0, 0xd5, 0x5e, 0x54, 0xd2, 0x70, 0x34, 0xc3, 0xc2, 0xcb, 0xb4, 0x79, 0xf0, 0x8a, 0x91, 0xe6, 0x7c, 0x5d, 0xbd, 0xe2, 0x09, 0x31, 0x59, 0x7e, 0x92, 0x97, 0xea, 0x5a, 0x1f, 0xd1, 0x72, 0xae, 0x69, 0x88, 0x85, 0xfb, 0x3f, 0x97, 0x37, 0x8b, 0xfc, 0x93, 0x71, 0x42, 0x1d, 0x58, 0xa5, 0xac, 0x49, 0x76, 0xcc, 0x25, 0xf2, 0x6f, 0x5b, 0x77, 0x42, 0x9f, 0xa9, 0xdc, 0xe7, 0x1c, 0xff, 0xb8, 0x62, 0xb3, 0x2b, 0x61, 0x4f, 0x1d, 0xf4, 0x64, 0xb0, 0x81, 0x7d, 0x08, 0xc2, 0xa4, 0x57, 0xbe, 0xd1, 0xb8, 0x33, 0x2d, 0xdd, 0xd1, 0x2e, 0xc9, 0x9b, 0x0c, 0x83, 0xde, 0xef, 0x55, 0x8f, 0xd3, 0xd9, 0xb7, 0x02, 0x37, 0x3b, 0xf7, 0x7f, 0x79, 0x9e, 0x7e, 0x79, 0x47, 0x1a, 0x04, 0x38, 0x0d, 0xbd, 0x98, 0x03, 0x83, 0x92, 0xf3, 0x8f, 0xbf, 0xfc, 0x2a, 0xca, 0x11, 0xfa, 0xcd, 0xb2, 0x68, 0xb5, 0x3e, 0x19, 0xc5, 0x25, 0x0e, 0xbf, 0x72, 0x2c, 0x56, 0xef, 0x4b, 0x07, 0x22, 0xd7, 0xea, 0x68, 0x0e, 0xba, 0xf9, 0xaa, 0xab, 0x74, 0x91, 0x5f, 0x66, 0xe5, 0xa3, 0x55, 0x26, 0x77, 0x19, 0x03, 0xb0, 0xbf, 0x76, 0x26, 0xbd, 0xad, 0xc3, 0x65, 0x39, 0x0a, 0xea, 0xcf, 0x3b, 0x55, 0x98, 0xc8, 0x17, 0xef, 0xd2, 0x85, 0x7c, 0x7e, 0xd3, 0x80, 0xd2, 0x0e, 0xd8, 0x9d, 0xd9, 0x5e, 0x27, 0x25, 0xbf, 0x7c, 0x6f, 0x11, 0x56, 0x7b, 0xbf, 0x2f, 0x3b, 0xdf, 0x22, 0x7e, 0xa1, 0x40, 0xc9, 0x99, 0x35, 0x11, 0x5f, 0x56, 0x23, 0x3d, 0xd6, 0xf5, 0xa5, 0xa4, 0xe8, 0x3d, 0xb1, 0xa7, 0xb6, 0x9d, 0xdc, 0x11, 0x1a, 0x8c, 0x9d, 0x74, 0x89, 0xae, 0xd4, 0x45, 0xfa, 0x93, 0x39, 0xc4, 0x33, 0x1a, 0xed, 0x31, 0x28, 0xda, 0x0f, 0x41, 0x9a, 0xb6, 0xb9, 0x09, 0x92, 0x84, 0x4e, 0xe1, 0xa2, 0x1c, 0xbf, 0x8f, 0xe3, 0xad, 0x4b, 0xbe, 0x27, 0xaf, 0x60, 0x40, 0xff, 0xf6, 0xfe, 0x25, 0x88, 0x34, 0x48, 0xe2, 0xf9, 0x77, 0xe0, 0xfd, 0x43, 0xaa, 0x0c, 0x16, 0xe9, 0x5c, 0xa3, 0xd3, 0xdf, 0x91, 0xe3, 0x7a, 0x94, 0x60, 0x8c, 0xdf, 0x42, 0x6a, 0x9f, 0xf4, 0x48, 0xa0, 0x7c, 0x95, 0x69, 0xcc, 0x53, 0x1f, 0x58, 0x80, 0xef, 0x7c, 0x39, 0xf8, 0x3f, 0x17, 0x5f, 0x14, 0x79, 0xb5, 0xa0, 0x8b, 0x07, 0x00, 0xfa, 0xef };
    var hash = [_]u32{0} ** 4;
    computeMd5(&message, &hash);
    const expected_hash = [4]u32{ 3824439167, 125395705, 3767690293, 3983405441 };
    try std.testing.expectEqual(expected_hash, hash);
}

test "message of 1016 bytes : matches builtin md5" {
    const message = [_]u8{ 0xff, 0xdd, 0x2b, 0x9b, 0x7f, 0x45, 0xde, 0x3a, 0xac, 0x32, 0xf1, 0x92, 0xb8, 0x0b, 0xb2, 0xc7, 0x7e, 0xca, 0x53, 0x05, 0x65, 0x01, 0x1b, 0x5f, 0x93, 0x34, 0xcb, 0x6e, 0x1f, 0xb1, 0xde, 0xdd, 0xb1, 0xf4, 0x77, 0x93, 0x46, 0xd6, 0xea, 0x65, 0x8f, 0x0a, 0x15, 0xde, 0x9b, 0x76, 0x1a, 0xef, 0xd7, 0x2a, 0x1d, 0xc9, 0x59, 0x77, 0xe9, 0x61, 0xae, 0x40, 0xf5, 0x06, 0xe7, 0x90, 0x2b, 0xf7, 0xc9, 0xdf, 0xf6, 0xed, 0x97, 0x5c, 0x37, 0xb8, 0x58, 0xe2, 0x99, 0xd3, 0x19, 0x6a, 0x14, 0xef, 0x4c, 0x53, 0xfd, 0xe6, 0x7e, 0x66, 0x94, 0x7c, 0xc4, 0x4c, 0x62, 0x09, 0x06, 0x75, 0xe6, 0xd7, 0xa6, 0x6b, 0x4d, 0xd4, 0x12, 0x7a, 0x9a, 0xb3, 0xad, 0x34, 0xaf, 0x6f, 0xe5, 0x52, 0x64, 0x80, 0x73, 0x14, 0x34, 0xd0, 0x24, 0x59, 0x37, 0x25, 0x44, 0xd3, 0xc0, 0x3c, 0x32, 0x2f, 0xee, 0x84, 0xb8, 0x36, 0x90, 0xaf, 0xd6, 0x3a, 0xb5, 0x55, 0x68, 0x6e, 0x16, 0xe9, 0xd4, 0x75, 0x7d, 0xcb, 0x38, 0x9e, 0xd3, 0x12, 0x5d, 0xe8, 0x95, 0xd2, 0x13, 0xb0, 0x41, 0x41, 0x81, 0x47, 0x23, 0x32, 0x06, 0x60, 0x9c, 0x52, 0x08, 0x62, 0x7c, 0xaa, 0x17, 0x81, 0x53, 0xf6, 0x61, 0x50, 0xcf, 0x8f, 0x5b, 0x96, 0x65, 0x90, 0x82, 0x50, 0x9d, 0x50, 0x0b, 0x5b, 0x2f, 0xdd, 0xf1, 0xe4, 0x5a, 0xab, 0xa9, 0x85, 0x67, 0x3c, 0x53, 0xc6, 0xee, 0x84, 0x7f, 0x45, 0x6d, 0x90, 0x2a, 0x89, 0x2e, 0xb6, 0xf0, 0x7e, 0xac, 0xd2, 0xac, 0x15, 0xd4, 0x16, 0x76, 0xf2, 0x41, 0xbe, 0xe1, 0x45, 0x96, 0xd4, 0x4f, 0x13, 0xe1, 0x1b, 0x63, 0xbe, 0x8a, 0x70, 0x15, 0xae, 0x67, 0x47, 0x70, 0x70, 0x3b, 0xa0, 0xdd, 0x6c, 0xbb, 0x67, 0x3b, 0xb8, 0x69, 0x0a, 0x97, 0x15, 0x7a, 0x9c, 0x96, 0xc8, 0x80, 0x8f, 0xb9, 0xe0, 0x3e, 0x98, 0x69, 0x9d, 0x54, 0xee, 0x83, 0xc9, 0xe1, 0xd7, 0x9b, 0x10, 0xe8, 0x20, 0x5f, 0x0e, 0xde, 0x5b, 0x53, 0x79, 0xd8, 0xd9, 0x21, 0x8f, 0x8c, 0xba, 0xb7, 0x83, 0x76, 0x52, 0x3d, 0x20, 0xcf, 0x21, 0x9a, 0x3f, 0x80, 0xd8, 0x29, 0x95, 0x81, 0x74, 0xb4, 0xce, 0x7f, 0xac, 0x85, 0x01, 0x0b, 0x7d, 0x5a, 0x2f, 0x4b, 0x2c, 0xbe, 0xcf, 0x28, 0x77, 0xd2, 0x6e, 0x95, 0x43, 0x44, 0x9d, 0xa9, 0x38, 0xb0, 0xa6, 0x0f, 0x58, 0x9a, 0x9f, 0x17, 0x21, 0xea, 0x9a, 0xd2, 0xf8, 0xb3, 0x7a, 0xda, 0x10, 0x7c, 0x2a, 0x39, 0x33, 0x89, 0x38, 0xa4, 0x01, 0xd5, 0x1a, 0x9b, 0xb8, 0xcd, 0x4a, 0xda, 0x27, 0x67, 0xa6, 0xf8, 0x2f, 0x1b, 0x7b, 0xa4, 0x90, 0x0e, 0xb1, 0x65, 0xf8, 0x21, 0x3b, 0x3b, 0x0b, 0x27, 0x29, 0xea, 0xc8, 0x94, 0x35, 0xd4, 0x4b, 0x95, 0xfa, 0x90, 0x92, 0xe9, 0x21, 0xdf, 0xac, 0x01, 0xa1, 0xa3, 0x41, 0x27, 0x00, 0xaa, 0x32, 0x16, 0xe9, 0xcb, 0xd5, 0x5a, 0xd7, 0x5f, 0xa1, 0x8f, 0x5c, 0xd4, 0x2a, 0x63, 0x28, 0x21, 0x02, 0x4a, 0x3b, 0x89, 0x0a, 0x3d, 0x50, 0x93, 0x64, 0xc3, 0x53, 0xd5, 0x16, 0xed, 0x5f, 0x72, 0x7f, 0x9d, 0x97, 0x87, 0x56, 0xbe, 0x4d, 0x9e, 0x49, 0x2b, 0x7d, 0x06, 0x8b, 0x6f, 0x22, 0x1c, 0xaa, 0x11, 0x2d, 0xee, 0x2a, 0x83, 0xb6, 0xe1, 0x1f, 0x76, 0xb3, 0x55, 0xed, 0xd0, 0x06, 0x37, 0x1e, 0x61, 0xfe, 0x17, 0xd7, 0x00, 0xed, 0x3b, 0xd6, 0x36, 0xef, 0x0f, 0x28, 0xa5, 0x6f, 0x21, 0x07, 0x69, 0x3b, 0x26, 0x5f, 0x09, 0xb7, 0xd8, 0x73, 0xe7, 0xd8, 0xe5, 0x38, 0xe6, 0x4e, 0x51, 0x33, 0xc4, 0x4c, 0x14, 0xe4, 0xa8, 0x8a, 0x5f, 0x5e, 0x2f, 0xf7, 0x18, 0x57, 0xe4, 0xf0, 0xd1, 0x8b, 0xb7, 0x75, 0x8e, 0x39, 0x30, 0x54, 0xf9, 0xf1, 0x67, 0xfd, 0x56, 0xd0, 0x7a, 0x02, 0xdf, 0xff, 0x4d, 0x30, 0x76, 0x4e, 0x91, 0x09, 0xa4, 0x15, 0x59, 0xfe, 0x1c, 0xf0, 0x83, 0x46, 0x6d, 0xee, 0xc2, 0xa7, 0x0d, 0xce, 0xee, 0x9e, 0xdb, 0x76, 0x4b, 0x87, 0xd4, 0x02, 0x8b, 0xae, 0x84, 0xff, 0x24, 0xf5, 0x75, 0x7b, 0x6c, 0x30, 0x05, 0x08, 0x3c, 0xe7, 0x78, 0xd8, 0xc8, 0xca, 0x56, 0xed, 0x37, 0x02, 0xc2, 0xc5, 0x4d, 0x75, 0x82, 0xe6, 0x6d, 0x26, 0xb3, 0xa2, 0x4a, 0xc5, 0x37, 0xdc, 0x99, 0x36, 0x9a, 0x9a, 0x3c, 0xd0, 0x20, 0xed, 0x22, 0x72, 0x3f, 0xfc, 0x71, 0x5c, 0x4f, 0xf0, 0x26, 0x53, 0x8b, 0x9e, 0xe9, 0x90, 0xf8, 0x7e, 0xa9, 0x00, 0x57, 0xab, 0xa0, 0x90, 0x3a, 0xe3, 0x9d, 0x1f, 0xdd, 0x5e, 0xd8, 0x3a, 0x06, 0xeb, 0x9b, 0xb1, 0x05, 0xe3, 0x2f, 0xf9, 0x2d, 0x7a, 0x83, 0xce, 0x73, 0x5f, 0x76, 0xe5, 0x10, 0xa3, 0x61, 0xee, 0x02, 0x88, 0xa6, 0xf4, 0xb3, 0x21, 0x47, 0x3b, 0x09, 0xd2, 0x6d, 0x09, 0x0e, 0x2e, 0xf9, 0x8e, 0x19, 0x31, 0x27, 0x28, 0x21, 0x4e, 0xa6, 0x66, 0x39, 0x69, 0x38, 0x4f, 0x64, 0xa0, 0xfa, 0xc6, 0xa2, 0x29, 0x2a, 0x02, 0x8d, 0xf2, 0x50, 0xd5, 0xaf, 0xdb, 0xf9, 0x32, 0x74, 0xb0, 0xd5, 0x5e, 0x54, 0xd2, 0x70, 0x34, 0xc3, 0xc2, 0xcb, 0xb4, 0x79, 0xf0, 0x8a, 0x91, 0xe6, 0x7c, 0x5d, 0xbd, 0xe2, 0x09, 0x31, 0x59, 0x7e, 0x92, 0x97, 0xea, 0x5a, 0x1f, 0xd1, 0x72, 0xae, 0x69, 0x88, 0x85, 0xfb, 0x3f, 0x97, 0x37, 0x8b, 0xfc, 0x93, 0x71, 0x42, 0x1d, 0x58, 0xa5, 0xac, 0x49, 0x76, 0xcc, 0x25, 0xf2, 0x6f, 0x5b, 0x77, 0x42, 0x9f, 0xa9, 0xdc, 0xe7, 0x1c, 0xff, 0xb8, 0x62, 0xb3, 0x2b, 0x61, 0x4f, 0x1d, 0xf4, 0x64, 0xb0, 0x81, 0x7d, 0x08, 0xc2, 0xa4, 0x57, 0xbe, 0xd1, 0xb8, 0x33, 0x2d, 0xdd, 0xd1, 0x2e, 0xc9, 0x9b, 0x0c, 0x83, 0xde, 0xef, 0x55, 0x8f, 0xd3, 0xd9, 0xb7, 0x02, 0x37, 0x3b, 0xf7, 0x7f, 0x79, 0x9e, 0x7e, 0x79, 0x47, 0x1a, 0x04, 0x38, 0x0d, 0xbd, 0x98, 0x03, 0x83, 0x92, 0xf3, 0x8f, 0xbf, 0xfc, 0x2a, 0xca, 0x11, 0xfa, 0xcd, 0xb2, 0x68, 0xb5, 0x3e, 0x19, 0xc5, 0x25, 0x0e, 0xbf, 0x72, 0x2c, 0x56, 0xef, 0x4b, 0x07, 0x22, 0xd7, 0xea, 0x68, 0x0e, 0xba, 0xf9, 0xaa, 0xab, 0x74, 0x91, 0x5f, 0x66, 0xe5, 0xa3, 0x55, 0x26, 0x77, 0x19, 0x03, 0xb0, 0xbf, 0x76, 0x26, 0xbd, 0xad, 0xc3, 0x65, 0x39, 0x0a, 0xea, 0xcf, 0x3b, 0x55, 0x98, 0xc8, 0x17, 0xef, 0xd2, 0x85, 0x7c, 0x7e, 0xd3, 0x80, 0xd2, 0x0e, 0xd8, 0x9d, 0xd9, 0x5e, 0x27, 0x25, 0xbf, 0x7c, 0x6f, 0x11, 0x56, 0x7b, 0xbf, 0x2f, 0x3b, 0xdf, 0x22, 0x7e, 0xa1, 0x40, 0xc9, 0x99, 0x35, 0x11, 0x5f, 0x56, 0x23, 0x3d, 0xd6, 0xf5, 0xa5, 0xa4, 0xe8, 0x3d, 0xb1, 0xa7, 0xb6, 0x9d, 0xdc, 0x11, 0x1a, 0x8c, 0x9d, 0x74, 0x89, 0xae, 0xd4, 0x45, 0xfa, 0x93, 0x39, 0xc4, 0x33, 0x1a, 0xed, 0x31, 0x28, 0xda, 0x0f, 0x41, 0x9a, 0xb6, 0xb9, 0x09, 0x92, 0x84, 0x4e, 0xe1, 0xa2, 0x1c, 0xbf, 0x8f, 0xe3, 0xad, 0x4b, 0xbe, 0x27, 0xaf, 0x60, 0x40, 0xff, 0xf6, 0xfe, 0x25, 0x88, 0x34, 0x48, 0xe2, 0xf9, 0x77, 0xe0, 0xfd, 0x43, 0xaa, 0x0c, 0x16, 0xe9, 0x5c, 0xa3, 0xd3, 0xdf, 0x91, 0xe3, 0x7a, 0x94, 0x60, 0x8c, 0xdf, 0x42, 0x6a, 0x9f, 0xf4, 0x48, 0xa0, 0x7c, 0x95, 0x69, 0xcc, 0x53, 0x1f, 0x58, 0x80, 0xef, 0x7c, 0x39, 0xf8, 0x3f, 0x17, 0x5f, 0x14, 0x79, 0xb5, 0xa0, 0x8b, 0x07, 0x00, 0xfa, 0xef };

    var hash = [_]u32{0} ** 4;
    computeMd5(&message, &hash);

    var builtin_hash = [_]u8{0} ** 16;
    std.crypto.hash.Md5.hash(&message, &builtin_hash, .{});
    const builtin_u32: [4]u32 = @as([*]const u32, @ptrCast(@alignCast(&builtin_hash)))[0..4].*;

    try std.testing.expectEqual(builtin_u32, hash);
}

test "short message : matches builtin md5" {
    const message = [_]u8{ 0xca, 0xfe, 0xba, 0xbe };
    const message_u32: []const u32 = @as([*]const u32, @ptrCast(@alignCast(&message)))[0..1];

    var hash = [_]u32{0} ** 4;
    try computeMd5_shortU32(message_u32, &hash);

    var builtin_hash = [_]u8{0} ** 16;
    std.crypto.hash.Md5.hash(&message, &builtin_hash, .{});
    const builtin_u32: [4]u32 = @as([*]const u32, @ptrCast(@alignCast(&builtin_hash)))[0..4].*;

    try std.testing.expectEqual(builtin_u32, hash);
}
