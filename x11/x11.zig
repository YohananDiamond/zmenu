const std = @import("std");

pub const display = @import("display.zig");
pub usingnamespace display;

pub const resource = @import("resource.zig");

test "entry point" {
    std.testing.refAllDecls(@This());
}
