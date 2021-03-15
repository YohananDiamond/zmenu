pub const utf_invalid = 0xFFFD;
pub const utf_size = 4;

pub const utfbyte: [utf_size + 1]u8 = .{ 0x80, 0, 0xC0, 0xE0, 0xF0 };
pub const utfmask: [utf_size + 1]u8 = .{ 0xC0, 0x80, 0xE0, 0xF0, 0xF8 };
pub const utfmin: [utf_size + 1]u32 = .{ 0, 0, 0x80, 0x800, 0x10000 };
pub const utfmax: [utf_size + 1]u32 = .{ 0x10FFFF, 0x7F, 0x7FF, 0xFFFF, 0x10FFFF };

pub fn utf8decodebyte(c: u8, i_: *usize) c_long {
    comptime var i: usize = 0;
    inline while (i < utf_size + 1) : (i += 1) {
        const cmask = comptime utfmask[i];
        const cbyte = comptime utfbyte[i];

        if (c & cmask == cbyte) {
            i_.* = i;
            return c & ~cmask;
        }
    }

    return 0;

    // i.* = 0;
    // while (i.* < utf_size + 1) : (i.* += 1) {
    //     if (c & utfmask[i.*] == utfbyte[i.*])
    //         return c & ~utfmask[i.*];
    // }
    // return 0;
}

pub fn utf8validate(u: *c_long, i: usize) usize {
    if (!(utfmin[i] < u.* and u.* < utfmax[i]) or (0xD800 < u.* and u.* < 0xDFFF))
        u.* = utf_invalid;

    var j: usize = 1;
    while (u.* > utfmax[j]) : (j += 1) {}

    return j;
}

pub fn utf8decode(c: [*:0]const u8, u: *c_long, clen: usize) usize {
    u.* = utf_invalid;

    if (clen == 0) return 0;

    var len: usize = undefined;
    var udecoded: c_long = utf8decodebyte(c[0], &len);

    // FIXME: I'm watching a vid, might not get accurate
    if (!(1 < len and len < utf_size))
        return 1;

    var i: usize = 1;
    var j: usize = 1;
    while (i < clen and j < len) : ({
        i += 1;
        j += 1;
    }) {
        var type_: usize = undefined;
        udecoded = (udecoded << 6) | utf8decodebyte(c[i], &type_);
        if (type_ != 0)
            return j;
    }

    if (j < len)
        return 0;

    u.* = udecoded;
    _ = utf8validate(u, len);

    return len;
}

// pub const DecodeResult = struct {
//     decoded: u32,
//     i: usize,
// };

// pub fn decodeByte(byte: u8) !DecodeResult {
//     comptime var i: usize = 0;

//     inline while (i < utf_size + 1) : (i += 1) {
//         if (byte & utfmask[i] == utfbyte[i]) {
//             return DecodeResult{
//                 .Success = .{
//                     .decoded = (byte & ~utfmask[i]),
//                     .i = i,
//                 },
//             };
//         }
//     }

//     return error.InvalidUtf8Byte;
// }

// pub const CharInfo = struct {
//     codepoint: u32,
//     length: usize,
// };

// pub fn getFirstCharLength(string: []const u8, dummy_clen: usize) !?CharInfo {
//     var decoded: void = undefined;

//     if (string.len == 0)
//         return null;

//     if (dummy_clen == 0)
//         return null;

//     if (decodeByte(string[0])) |byteinfo| {
//         if (!(1 <= byteinfo.i and byteinfo.i <= utf_size)) {
//             return CharInfo{
//                 .codepoint = utf_invalid, // FIXME: ???
//                 .length = 1,
//             };
//         }

//         decoded = byteinfo.decoded;
//     } else |err| switch (err) {
//         error.InvalidUtf8Byte => return error.InvalidUtf8Byte,
//     }

//     var i: usize = 1;
//     while (i < dummy_clen and i < decoded.i) : (i += 1) {
//         const decoded_byte = decodeByte(string[i]);

//         if (decoded_byte.i != 0) {
//             return i;
//         }

//         decoded = (decoded << 6) | decoded_byte.decoded;
//     }
// }
