pub const display = @import("display.zig");
pub usingnamespace display;

pub const resource = @import("resource.zig");

test "entry point" {
    _ = display;
    _ = resource;
}
