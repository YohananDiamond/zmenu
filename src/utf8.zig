// TODO: better naming

pub const utf_invalid = 0xFFFD;
pub const utf_size = 4;

pub const utfbyte: [utf_size + 1]u8 = .{ 0x80, 0x00, 0xC0, 0xE0, 0xF0 };
pub const utfmask: [utf_size + 1]u8 = .{ 0xC0, 0x80, 0xE0, 0xF0, 0xF8 };
pub const utfmin: [utf_size + 1]u32 = .{ 0x00, 0x00, 0x80, 0x800, 0x10000 };
pub const utfmax: [utf_size + 1]u32 = .{ 0x10FFFF, 0x7F, 0x7FF, 0xFFFF, 0x10FFFF };

pub const CharsIterator = struct {
    const Self = @This();

    position: usize,
    string: [:0]const u8,

    pub fn init(string: [:0]const u8) Self {
        return Self{
            .string = string,
            .position = 0,
        };
    }

    pub fn next(self: *Self) ?[]const u8 {
        if (self.position < self.string.len) {
            const slice = self.string[self.position..];
            const decoded = decode(slice, utf_size);

            const start = self.position;
            const end = self.position + decoded.length;

            self.position += decoded.length;
            return self.string[start..end];
        } else {
            return null;
        }
    }
};

pub const DecodedByte = struct {
    masked_c: c_long,
    dummy_value: usize,
};

pub fn decodeByte(byte: u8) DecodedByte {
    comptime var i: usize = 0;
    inline while (i < utf_size + 1) : (i += 1) {
        const cur_mask = comptime utfmask[i];
        const cur_byte = comptime utfbyte[i];

        if (byte & cur_mask == cur_byte)
            return DecodedByte{
                .masked_c = byte & ~cur_mask,
                .dummy_value = i,
            };
    }

    return DecodedByte{
        .masked_c = 0,
        .dummy_value = 0,
    };
}

pub fn validate(u: *c_long, i: usize) usize {
    if (!(utfmin[i] < u.* and u.* < utfmax[i]) or (0xD800 < u.* and u.* < 0xDFFF))
        u.* = utf_invalid;

    var j: usize = 1;
    while (u.* > utfmax[j]) : (j += 1) {}

    return j;
}

pub const CharInfo = struct {
    length: usize,
    dummy_value: c_long,
};

pub fn decode(
    string: [*:0]const u8,
    max_char_size: usize,
) CharInfo {
    if (max_char_size == 0)
        return CharInfo{
            .length = 0,
            .dummy_value = utf_invalid,
        };

    const first_byte = decodeByte(string[0]);
    const first_byte_len = first_byte.dummy_value;

    var udecoded = first_byte.masked_c;

    if (first_byte_len == 0 or utf_size < first_byte_len) // FIXME: utf_size < len... too big?
        return CharInfo{
            .length = 1,
            .dummy_value = utf_invalid,
        };

    var i: usize = 1;
    const char_limit = std.math.min(max_char_size, first_byte_len);

    while (i < char_limit) : (i += 1) {
        const current = decodeByte(string[i]);

        udecoded = (udecoded << 6) | current.masked_c;

        if (current.dummy_value != 0)
            return CharInfo{
                .length = 0,
                .dummy_value = utf_invalid,
            };
    }

    if (i < first_byte_len)
        return CharInfo{
            .length = 1,
            .dummy_value = utf_invalid,
        };

    var idk: c_long = undefined;
    _ = validate(&idk, first_byte_len);

    return CharInfo{
        .length = first_byte_len,
        .dummy_value = idk,
    };
}
