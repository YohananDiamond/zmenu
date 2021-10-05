const std = @import("std");
const x11 = @import("x11.zig");

const gmath = @import("gmath");
const Point2 = gmath.Point2;
const Rect2 = gmath.Rect2;
const c = @import("bindings.zig");

/// TODO: doc
pub const RawContext = c.GC;

/// TODO: doc
pub const PixmapID = c.Pixmap;

/// TODO: doc
pub const Context = struct {
    window: x11.WindowRef,
    context: RawContext,
    pixmap: PixmapID,

    const Self = @This();

    /// Initialize the context with a specific window and size.
    pub fn init(window: x11.WindowRef, size: Point2(u32)) Self {
        // TODO: gc args

        var context = c.XCreateGC(
            window._display_ptr,
            window._window_id,
            0,
            null,
        );
        errdefer c.XFreeGC(window._display_ptr, context);

        var pixmap = c.XCreatePixmap(
            window._display_ptr,
            window._window_id,
            @as(c_uint, size.x),
            @as(c_uint, size.y),
            c.x11_defaultdepth(window._display_ptr, window._screen_id), // TODO: allow to specify depth
        );
        errdefer c.XFreePixmap(window._display_ptr, pixmap);

        // TODO: proper configuration for line attributes
        std.debug.assert(c.XSetLineAttributes(
            window._display_ptr,
            context,
            1, // line width
            c.LineSolid,
            c.CapButt,
            c.JoinMiter,
        ) == 1);

        return Self{
            .window = window,
            .context = context,
            .pixmap = pixmap,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = c.XFreeGC(self.window._display_ptr, self.context);
        _ = c.XFreePixmap(self.window._display_ptr, self.pixmap);
    }

    /// TODO: doc
    fn setColor(self: *Self, color: Pixel) void {
        std.debug.assert(c.XSetForeground(
            self.window._display_ptr,
            self.context,
            color._data,
        ) == 1);
    }

    pub const RectFillMode = enum {
        Filled,
        Outline,
    };

    pub fn drawRect(self: *Self, rect: Rect2(i32, u32), color: Pixel, mode: RectFillMode) void {
        self.setColor(color);

        switch (mode) {
            .Filled => {
                std.debug.assert(c.XFillRectangle(
                    self.window._display_ptr,
                    self.window._window_id,
                    self.context,
                    @as(c_int, rect.x),
                    @as(c_int, rect.y),
                    @as(c_uint, rect.w),
                    @as(c_uint, rect.h),
                ) == 1);
            },
            .Outline => {
                std.debug.assert(c.XDrawRectangle(
                    self.window._display_ptr,
                    self.window._window_id,
                    self.context,
                    @as(c_int, rect.x),
                    @as(c_int, rect.y),
                    @as(c_uint, if (rect.w == 0) 0 else rect.w - 1),
                    @as(c_uint, if (rect.h == 0) 0 else rect.h - 1),
                ) == 1);
            },
        }
    }

    pub fn drawString(self: *Self, string: []const u8, at: Point2(i32)) void {
        _ = c.XDrawString(
            self.window._display_ptr,
            self.window._window_id,
            self.context,
            @as(c_int, at.x),
            @as(c_int, at.y),
            string.ptr,
            @intCast(c_int, string.len),
        );
    }
};

/// TODO: doc
pub const Pixel = struct {
    _data: c_ulong,

    const Self = @This();

    /// TODO: doc
    pub fn withColors(colors: struct { r: u8, g: u8, b: u8, a: u8 }) Self { // TODO: default value for alpha
        unreachable; // TODO
    }

    // From https://justpaste.it/974m7
    //
    // TODO: prove it's right (and does endianess matter?)
    pub fn fromRGB(r: u8, g: u8, b: u8) Self {
        return Self{
            ._data = @as(c_ulong, b) + (@as(c_ulong, g) << 8) + (@as(c_ulong, r) << 16),
        };
    }
};
