const build_options = @import("build_options");
const apis = @import("../apis.zig");
const xorg = apis.xorg;
const c = apis.bindings;
const Display = xorg.Display;

comptime {
    if (!build_options.use_xinerama) {
        @compileError("Attempt to use Xinerama while it is not available");
    }
}

pub const ScreenInfo = c.XineramaScreenInfo;

pub const ScreenQueries = struct {
    const Self = @This();

    screens: []ScreenInfo,

    pub fn deinit(self: *Self) void {
        xorg.internal.freeResource(self.screens.ptr);
    }
};

pub fn queryScreens(display: *const Display) ?ScreenQueries {
    var len: c_int = undefined;

    if (c.XineramaQueryScreens(display.ptr, &len)) |queries| {
        return ScreenQueries{ .screens = queries[0..@intCast(usize, len)] };
    } else {
        return null;
    }
}
