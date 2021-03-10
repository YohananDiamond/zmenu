pub fn charLength(string: []const u8) usize {
    unreachable;
}

// pub const utf_invalid = 0xFFFD;
// pub const utf_size = 4;

// // FIXME: figure out what each of these mean
// pub const utfbyte: [utf_size + 1]u8 = .{ 0x80, 0, 0xC0, 0xE0, 0xF0 };
// pub const utfmask: [utf_size + 1]u8 = .{ 0xC0, 0x80, 0xE0, 0xF0, 0xF8 };
// pub const utfmin: [utf_size + 1]u32 = .{ 0, 0, 0x80, 0x800, 0x10000 };
// pub const utfmax: [utf_size + 1]u32 = .{ 0x10FFFF, 0x7F, 0x7FF, 0xFFFF, 0x10FFFF };

// // #define UTF_INVALID 0xFFFD
// // #define UTF_SIZ     4

// // static const unsigned char utfbyte[UTF_SIZ + 1] = {0x80,    0, 0xC0, 0xE0, 0xF0};
// // static const unsigned char utfmask[UTF_SIZ + 1] = {0xC0, 0x80, 0xE0, 0xF0, 0xF8};
// // static const long utfmin[UTF_SIZ + 1] = {       0,    0,  0x80,  0x800,  0x10000};
// // static const long utfmax[UTF_SIZ + 1] = {0x10FFFF, 0x7F, 0x7FF, 0xFFFF, 0x10FFFF};

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
