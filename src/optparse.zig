const std = @import("std");

pub fn getLongOption(string: []const u8) ?[]const u8 {
    return if (string[0] == '-' and string[1] == '-') string[2..] else null;
}

pub fn getShortOption(string: []const u8) ?[]const u8 {
    return if (string[0] == '-' and string[1] != '-') string[1..] else null;
}

pub fn isOption(string: []const u8) bool {
    return string[0] == '-';
}

pub fn getPositionalOption(string: []const u8) ?[]const u8 {
    return if (string[0] != '-') string else null;
}

pub fn isLongOrShort(string: []const u8, long: ?[]const u8, short: ?[]const u8) bool {
    if (getLongOption(string)) |opt| {
        return if (long) |long_|
            std.mem.eql(u8, opt, long_)
        else
            false;
    } else if (getShortOption(string)) |opt| {
        return if (short) |short_|
            std.mem.eql(u8, opt, short_)
        else
            false;
    } else {
        return false;
    }
}
