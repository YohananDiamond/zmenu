const std = @import("std");

pub const c = @import("bindings.zig"); // FIXME: make this private

pub const display = @import("display.zig");

// pub const event = @import("event.zig");

pub const resource = @import("resource.zig");
pub const Resource = resource.Resource;
pub const ResourceManager = resource.ResourceManager;

pub const draw = @import("draw.zig");

pub const special = struct {
    pub const copy_from_parent: comptime_int = c.CopyFromParent;
};

pub const event_masks = struct {
    pub const exposure_mask = c.ExposureMask;
    pub const key_press_mask = c.KeyPressMask;
    pub const visibility_change_mask = c.VisibilityChangeMask;
};

test "entry point" {
    std.testing.refAllDecls(@This());
}
