const std = @import("std");
const testing = std.testing;

const x11 = @import("x11.zig");
const c = @import("bindings.zig");

pub const Resource = struct {
    value: [:0]const u8,
    type_: [*:0]const u8 = "String",
};

/// Is responsible for loading and setting X resources.
pub const ResourceManager = struct {
    /// The inner X database type.
    _db: c.XrmDatabase,

    const Self = @This();
    pub const InitError = error{NoXrmString};

    pub fn init(display: x11.DisplayRef) InitError!Self {
        c.XrmInitialize();

        const xrm_string = c.XResourceManagerString(display._ptr) orelse return InitError.NoXrmString;

        return Self{
            ._db = c.XrmGetStringDatabase(xrm_string) orelse unreachable,
        };
    }

    pub fn deinit(self: *Self) void {
        c.XrmDestroyDatabase(self._db);
    }

    pub fn getResource(self: *const Self, name: [*:0]const u8, class: ?[*:0]const u8) ?Resource {
        var value: c.XrmValue = undefined;
        var type_: [*c]u8 = undefined;

        if (c.XrmGetResource(self._db, name, class orelse name, &type_, &value) != 0) {
            return Resource{
                .value = std.meta.assumeSentinel(value.addr[0..value.size], 0),
                .type_ = std.meta.assumeSentinel(@ptrCast([*:0]const u8, type_), 0),
            };
        } else {
            return null;
        }
    }

    pub fn setResource(self: *Self, specifier: [*:0]const u8, resource: Resource) void {
        // FIXME: should the strings in `resource` live as long as the database?

        var value: c.XrmValue = undefined;
        value.addr = @intToPtr([*c]u8, @ptrToInt(resource.value.ptr));
        value.size = @intCast(c_uint, resource.value.len);

        c.XrmPutResource(&self._db, specifier, resource.type_, &value);
    }
};

test "double Xrm initialization should not be an issue, right?" {
    c.XrmInitialize();
    c.XrmInitialize();
}

test "ResourceManager.getResource" {
    var display = try x11.Display.init(null);
    defer display.deinit();

    var resource_manager = try x11.resource.ResourceManager.init(display.asRef());
    defer resource_manager.deinit();

    const name = "exampleName";
    const class = "exampleClass";
    _ = resource_manager.getResource(name, class);
}

test "ResourceManager.setResource" {
    var display = try x11.Display.init(null);
    defer display.deinit();

    var resource_manager = try x11.resource.ResourceManager.init(display.asRef());
    defer resource_manager.deinit();

    resource_manager.setResource("__resourceManagerTest.value", .{ .value = "Hello, World!" });

    testing.expect(std.mem.eql(
        u8,
        "Hello, World!",
        resource_manager.getResource("__resourceManagerTest.value", null).?.value,
    ));
}
