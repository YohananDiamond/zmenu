const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const c = @import("_bindings.zig");

pub const internal = struct {
    pub fn freeResource(resource: *c_void) void {
        // XFree seems to always return 1. It doesn't even seem to throw any X error.
        std.debug.assert(c.XFree(resource) == 1);
    }
};

pub const WindowID = c.Window;
pub const ScreenID = c_int; // FIXME: is this the best type? can screen IDs can be negative?
pub const PixmapID = c.Pixmap;
pub const WindowAttributes = c.XWindowAttributes;
pub const GraphicalContext = c.GC;

pub const pointer_root_window = c.PointerRoot;
pub const no_window = c.None;

pub const WindowTriplet = struct {
    display: *Display,
    screen_id: ScreenID,
    window_id: WindowID,
};

pub const Display = struct {
    const Self = @This();

    pub const OpenDisplayError = error{OpenDisplayError};

    ptr: *c.Display,

    pub fn init() OpenDisplayError!Self {
        return Self{
            .ptr = c.XOpenDisplay(0) orelse return error.OpenDisplayError,
        };
    }

    pub fn fromPtr(ptr: *c.Display) callconv(.Inline) Self {
        return Self{ .ptr = ptr };
    }

    pub fn deinit(self: *Self) void {
        // XCloseDisplay actually returns a c_int but as far as I've read it is always zero.
        //
        // My source of information: https://github.com/mirror/libX11/blob/master/src/ClDisplay.c#L73
        const result = c.XCloseDisplay(self.ptr);
        std.debug.assert(result == 0);
    }
};

pub fn defaultScreenID(display: *const Display) ScreenID {
    return c.ext_defaultscreen(display.ptr);
}

pub fn rootWindowID(display: *const Display, screen_id: ScreenID) WindowID {
    return c.ext_rootwindow(display.ptr, screen_id);
}

pub fn windowAttributes(display: *const Display, window_id: WindowID) ?WindowAttributes {
    var wa: WindowAttributes = undefined;
    const result = c.XGetWindowAttributes(display.ptr, window_id, &wa);

    return if (result != 0) wa else null;
}

pub fn grabKeyboard(display: *const Display, window_id: WindowID) error{CouldNotGrabKeyboard}!void {
    // TODO: study properly XGrabKeyboard and add more options, possibly
    const result = c.XGrabKeyboard(
        display.ptr,
        window_id,
        @boolToInt(true),
        c.GrabModeAsync,
        c.GrabModeAsync,
        c.CurrentTime,
    );

    if (result != c.GrabSuccess)
        return error.CouldNotGrabKeyboard;
}

pub const ResourceManager = struct {
    const Self = @This();

    pub const InitError = error{NoXrmString};

    database: c.XrmDatabase,

    /// NOTE: the returned resource manager
    pub fn init(display: *const Display) InitError!Self {
        c.XrmInitialize();

        const xrm_string = c.XResourceManagerString(display.ptr) orelse return InitError.NoXrmString;

        return Self{
            .database = c.XrmGetStringDatabase(xrm_string) orelse unreachable,
        };
    }

    pub fn deinit(self: *Self) void {
        c.XrmDestroyDatabase(self.database);
    }

    // pub fn getResource(self: *const Self, resource_name: [:0]const u8) ?Resource {}
};

pub const Color = struct {
    const Self = @This();

    color: c.XftColor,

    pub const InitError = error{CouldNotAllocateColor};

    pub fn parse(
        string: [*:0]const u8,
        display: *const Display,
        screen_id: ScreenID,
    ) InitError!Self {
        var self = Self{ .color = undefined };
        const display_ptr = display.ptr;

        // FIXME: verify if this usage of XftColorAllocName is right
        const result = c.XftColorAllocName(
            display_ptr,
            c.ext_defaultvisual(display_ptr, screen_id),
            c.ext_defaultcolormap(display_ptr, screen_id),
            string,
            &self.color,
        );

        return if (result == 0)
            InitError.CouldNotAllocateColor
        else
            self;
    }

    pub fn deinit(self: *Self) void {
        c.XftColorFree(&self.color); // FIXME: not sure if this is right either
    }
};

pub fn hasLocaleSupport() bool {
    if (c.setlocale(c.LC_CTYPE, "") == null) return false;
    if (c.XSupportsLocale() != 1) return false;

    return true;
}

pub const Font = struct {
    const Self = @This();

    triplet: *const WindowTriplet,
    font: *c.XftFont,
    pattern: ?*c.FcPattern,

    pub const FontResource = union(enum) {
        Name: [:0]const u8,
        Pattern: *c.FcPattern,
    };

    pub const Error = error{
        SkipFontLoad,
        CouldNotLoadFont,
        CouldNotParseFontName,
    }; // FIXME: are CouldNotLoadFont and CouldNotParseFontName right names?

    pub fn init(resource: FontResource, triplet: *const WindowTriplet) Error!Self {
        var pattern: ?*c.FcPattern = null;

        const font = switch (resource) {
            .Name => |name| blk: {
                const xft_font = c.XftFontOpenName(
                    triplet.display.ptr,
                    triplet.screen_id,
                    name,
                ) orelse return Error.CouldNotLoadFont;
                errdefer c.XftFontClose(triplet.display.ptr, xft_font);

                // There's a pattern pointer at `xft_font.*.pattern` but it doesn't necessarily yield the same results
                // as the ones FcNameParse does.
                //
                // Accessing by the pointer in the font might result in some missing-character rectangles being drawn.
                //
                // FIXME: is this related to fallback fonts?
                pattern = c.FcNameParse(name) orelse return Error.CouldNotParseFontName;

                break :blk xft_font;
            },
            .Pattern => |patt| blk: {
                break :blk c.XftFontOpenPattern(triplet.display.ptr, patt) orelse return Error.CouldNotLoadFont;
            },
        };
        errdefer c.XftFontClose(triplet.display.ptr, font);

        // This block below is a workaround modelled around Xterm's one, which disallows using color fonts so Xft
        // doesn't throw a BadLength error with color glyphs.
        //
        // More info:
        // * https://bugzilla.redhat.com/show_bug.cgi?id=1498269
        // * https://lists.suckless.org/dev/1701/30932.html
        // * https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=916349
        {
            var iscol: c_int = undefined; // FIXME: ugly name
            if (@enumToInt(c.FcPatternGetBool(font.*.pattern, c.FC_COLOR, 0, &iscol)) == c.FcResultMatch and iscol != 0) { // FIXME: study this
                return Error.SkipFontLoad;
            }
        }

        return Self{
            .triplet = triplet,
            .pattern = pattern,
            .font = font,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.pattern) |patt|
            c.FcPatternDestroy(patt);

        c.XftFontClose(self.triplet.display.ptr, self.font);
    }

    pub fn height(self: *const Self) callconv(.Inline) usize {
        return @intCast(usize, self.font.*.ascent + self.font.*.descent);
    }
};

pub const Fontset = struct {
    const Self = @This();

    fonts: ArrayList(Font),
    allocator: *Allocator,
    triplet: *const WindowTriplet,

    pub const Error = Font.Error || error{NoFont};

    pub fn init(
        font_names: []const [:0]const u8,
        allocator: *Allocator,
        triplet: *const WindowTriplet,
    ) (Error || Allocator.Error)!Self {
        var fonts = ArrayList(Font).init(allocator);
        errdefer {
            for (fonts.items) |*font| font.deinit();
            fonts.deinit();
        }

        for (font_names) |fname| { // TODO: reserve at least a little bit of space
            var font = Font.init(.{ .Name = fname }, triplet) catch |err| switch (err) {
                Font.Error.SkipFontLoad => continue,
                else => return err,
            };
            errdefer font.deinit();

            try fonts.append(font);
        }

        if (fonts.items.len == 0)
            return Error.NoFont;

        return Self{
            .fonts = fonts,
            .triplet = triplet,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.fonts.items) |*font|
            font.deinit();

        self.fonts.deinit();
    }

    pub fn lrpad(self: *const Self) usize { // FIXME: figure out what this is and find a better way to calculate it
        return self.fonts.items[0].height();
    }
};

pub const Pixmap = @compileError("TODO");
