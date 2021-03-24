const std = @import("std");

const Point2 = @import("point.zig").Point2;

const utf8 = @import("utf8.zig");

const xorg = @import("apis/xorg.zig");
const WindowTriplet = xorg.WindowTriplet;

const c = @import("apis/_bindings.zig"); // FIXME: stop using this here

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
                c.zmenu_defaultdepth(triplet.display.ptr, triplet.screen_id),
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
        xorg.internal.freePixmap(self.triplet.display, self.pixmap);
        xorg.internal.freeGraphicalContext(self.triplet.display, self.context);
    }

    pub fn resize(self: *Self, new_size: Point2(u32)) void {
        // update width and height values
        self.size = new_size;

        // free old pixmap and create a new one
        xorg.internal.freePixmap(self.triplet.display, self.pixmap);
        self.pixmap = c.XCreatePixmap(
            self.triplet.display.ptr,
            self.triplet.window_id,
            @as(c_uint, new_size.x),
            @as(c_uint, new_size.y),
            c.zmenu_defaultdepth(self.triplet.display.ptr, self.triplet.screen_id),
        );
    }

    pub fn getTextWidth(
        self: *const Self,
        text: []const u8,
    ) usize {
        return 200; // FIXME: dummy value

        // const mut_self = @intToPtr(*Self, @ptrToInt(self));

        // while (true) {
        //     var string_len: usize = 0;

        //     var i: usize = 0;
        //     while (i < text.len) {
        //         const decoded = utf8.decode(text[i..], utf_siz);
        //         const length = decoded.len;
        //         const codepoint = decoded.dummy_value;

        //         for (self.fontset.fonts.items) |*font| {
        //             const char_exists = c.XftCharExists(
        //                 self.triplet.display.ptr,
        //                 font.font,
        //                 codepoint,
        //             );

        //             if (char_exists) {
        //                 string_len += length;
        //                 i += length;
        //             }
        //         }
        //     }
        // }
    }

    ///////////////////////////////////////////////////

    /// Set the color to be used on the next draw operation.
    pub fn setColor(self: *Self, color: *const xorg.Color) void {
        std.debug.assert(c.XSetForeground(
            self.triplet.display.ptr,
            self.context,
            color.pixel(),
        ) == 1);
    }

    const RectFill = enum {
        Filled,
        Outline,
    };

    pub fn drawRectWithLastColor(
        self: *Self,
        top_left: Point2(i32),
        size: Point2(u32),
        mode: RectFill, // FIXME(someday): this could be an inline argument
    ) void {
        switch (mode) {
            .Filled => {
                std.debug.assert(c.XFillRectangle(
                    self.triplet.display.ptr,
                    self.pixmap,
                    self.context,
                    @as(c_int, top_left.x),
                    @as(c_int, top_left.y),
                    @as(c_uint, size.x),
                    @as(c_uint, size.y),
                ) == 1);
            },
            .Outline => {
                std.debug.assert(c.XDrawRectangle(
                    self.triplet.display.ptr,
                    self.pixmap,
                    self.context,
                    @as(c_int, top_left.x),
                    @as(c_int, top_left.y),
                    @as(c_uint, size.x - 1), // FIXME: will crash when size.x == 0
                    @as(c_uint, size.y - 1), // FIXME: will crash when size.x == 0
                ) == 1);
            },
        }
    }

    pub fn drawRect(
        self: *Self,
        top_left: Point2(i32),
        size: Point2(u32), // TODO: combine both args into a rect type
        mode: RectFill, // FIXME(someday): this could be an inline argument
        color: *const xorg.Color,
    ) void {
        self.setColor(color);
        self.drawRectWithLastColor(top_left, size, mode);
    }

    pub fn drawText(
        self: *Self,
        text: [:0]const u8,
        pos: Point2(i32),
        size: Point2(u32),
        left_padding: u32, // FIXME: ???
        fg_color: *const xorg.Color,
        bg_color: *const xorg.Color,
    ) struct { text_width: u32 } {
        // assume `render = true`

        self.setColor(bg_color);
        self.drawRectWithLastColor(
            pos,
            size,
            .Filled
        );

        const dummy_d: ?*c.XftDraw = c.XftDrawCreate(
            self.triplet.display.ptr,
            self.pixmap,
            c.zmenu_defaultvisual(self.triplet.display.ptr, self.triplet.screen_id),
            c.zmenu_defaultcolormap(self.triplet.display.ptr, self.triplet.screen_id),
        );

        var x = left_padding;
        var w = left_padding;

        return .{ .text_width = 0 }; // FIXME
    }
};
