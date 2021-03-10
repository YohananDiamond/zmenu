const Point2 = @import("point.zig").Point2;

const xorg = @import("apis/xorg.zig");
const WindowTriplet = xorg.WindowTriplet;

const c = struct { // FIXME: stop using this here
    pub usingnamespace @import("apis/_bindings.zig");
};

pub const DrawControl = struct {
    triplet: *const WindowTriplet,
    size: Point2(u32),
    context: xorg.GraphicalContext,
    pixmap: xorg.PixmapID,
    fontset: *const xorg.Fontset,

    const Self = @This();

    pub fn init(
        triplet: *const WindowTriplet,
        size: Point2(u32),
        fontset: *const xorg.Fontset,
    ) Self {
        var self = Self{
            .size = size,
            .pixmap = c.XCreatePixmap(
                triplet.display.ptr,
                triplet.window_id,
                @intCast(c_uint, size.x),
                @intCast(c_uint, size.y),
                c.ext_defaultdepth(triplet.display.ptr, triplet.screen_id),
            ),
            .context = c.XCreateGC(triplet.display.ptr, triplet.window_id, 0, null), // FIXME: what is 0 and null
            .fontset = fontset,
            .triplet = triplet,
        };

        _ = c.XSetLineAttributes( // FIXME: ignoring empty value
            triplet.display.ptr,
            self.context,
            1,
            c.LineSolid,
            c.CapButt,
            c.JoinMiter,
        ); // TODO: maybe turn this into a wrapped function

        return self;
    }

    pub fn deinit(self: *Self) void {
        _ = c.XFreePixmap(self.triplet.display.ptr, self.pixmap); // FIXME: ignoring unknown value
        _ = c.XFreeGC(self.triplet.display.ptr, self.context); // FIXME: ignoring unknown value
    }

    pub fn resize(self: *Self, new_size: Point2(u32)) void {
        // update width and height values
        self.size = new_size;

        // free old pixmap and create a new one
        _ = c.XFreePixmap(self.display.ptr, self.pixmap); // FIXME: ignoring unknown value
        self.pixmap = c.XCreatePixmap(
            self.display.ptr,
            self.window_id,
            @as(c_uint, new_size.x),
            @as(c_uint, new_size.y),
            c.ext_defaultdepth(self.display.ptr, self.screen_id),
        );
    }

    pub fn getTextWidth(self: *const Self, text: []const u8) usize {
        return Self.drawText(
            @intToPtr(*Self, @ptrToInt(self)), // casting away the const because we won't really draw anything
            text,
            DrawMode.GetWidth,
            // DrawMode{ .GetWidth },
            0,
            0,
        );
    }

    pub const DrawMode = union(enum) {
        Render: struct {
            position: Point2(i32),
            size: Point2(u32),
        },
        GetWidth: void,
    };

    pub fn drawText(
        self: *Self,
        text: []const u8,
        mode: DrawMode,
        left_padding: u32, // FIXME: ???
        invert: anytype, // FIXME: ???
    ) usize {
        const used_font = self.fontset.fonts;

        unreachable;
    }
};
