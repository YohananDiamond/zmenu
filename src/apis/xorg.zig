// TODO: refactor this into a separate package

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const api = @import("../apis.zig");
const c = api.bindings;

pub const WindowID = c.Window;
pub const ScreenID = c_int; // FIXME: is this the best type? can screen IDs can be negative?
pub const PixmapID = c.Pixmap;
pub const WindowAttributes = c.XWindowAttributes;
pub const GraphicalContext = c.GC;
pub const Timestamp = c.Time;

pub const current_time: Timestamp = 0;
pub const pointer_root: WindowID = c.PointerRoot;
pub const none: WindowID = c.None;

pub const defaultScreenID = @compileError("This function deprecated - use Display.defaultScreenID instead");

pub fn hasLocaleSupport() bool {
    if (c.setlocale(c.LC_CTYPE, "") == null) return false;
    if (c.XSupportsLocale() != 1) return false;

    return true;
}

pub const Display = struct {
    ptr: *c.Display,

    const Self = @This();

    pub const OpenError = error{FailedToOpenDisplay};

    pub const InitOptions = struct {
        display_name: ?[:0]const u8 = null,
    };

    pub fn init(options: InitOptions) OpenError!Self {
        return Self{ .ptr = c.XOpenDisplay(null) orelse return OpenError.FailedToOpenDisplay };
    }

    pub fn deinit(self: *Self) void {
        // XCloseDisplay actually returns a c_int but as far as I've read it is always zero.
        // https://github.com/mirror/libX11/blob/master/src/ClDisplay.c#L73
        std.debug.assert(c.XCloseDisplay(self.ptr) == 0);
    }

    /// TODO: doc
    pub fn defaultScreenID(self: *const Self) ScreenID {
        return c.zmenu_defaultscreen(self.ptr);
    }

    /// TODO: doc
    pub fn rootWindowID(self: *const Self, screen_id: ScreenID) WindowID {
        return c.zmenu_rootwindow(display.ptr, screen_id);
    }

    /// TODO: doc
    pub fn rootWindowOf(self: *const Self, screen_id: ScreenID) WindowID {
        return Window{
            .display = self,
            .screen_id = id,
            .window_id = self.rootWindowID(screen_id),
        };
    }

    /// TODO: doc
    ///
    /// Window must not live longer than `self`.
    pub fn rootWindow(self: *Self) Window {
        const default_screen = self.defaultScreenID();
        return self.rootWindowOf(default_screen);
    }

    /// Initialize a display from a raw X display pointer.
    pub fn fromRawPtr(ptr: *c.Display) Self {
        return Self{ .ptr = ptr };
    }
};

test "open and close display" {
    var display = try Display.init(.{});
    defer display.deinit();
}

/// TODO: doc
///
/// This struct does not have init or deinit methods, as it does not need them.
pub const Window = struct {
    display: *Display,
    screen_id: ScreenID,
    window_id: WindowID,

    pub fn attributes(self: *const Self) ?WindowAttributes {
        var wa: WindowAttributes = undefined;
        const result = c.XGetWindowAttributes(self.display.ptr, self.window_id, &wa);

        return if (result != 0) wa else null;
    }

    pub const GrabKeyboadOptions = struct {
        pub const SyncOrAsync = enum {
            Sync = 0,
            Async = 1,
        };

        owner_events: bool,
        pointer_mode: SyncOrAsync,
        keyboard_mode: SyncOrAsync,
        time: Timestamp,
    };

    pub const GrabKeyboardError = error{FailedToGrabKeyboard};

    pub fn grabKeyboard(self: *Self, options: GrabKeyboadOptions) GrabKeyboardError!void {
        if (c.XGrabKeyboard(
            self.display.ptr,
            self.display.window_id,
            @boolToInt(options.owner_events),
            @enumToInt(options.pointer_mode),
            @enumToInt(options.keyboard_mode),
            options.time,
        ) != c.GrabSuccess)
            return GrabKeyboardError.FailedToGrabKeyboard;
    }

    pub const ClassHints = struct {
        name: ?[*:0]const u8,
        class: ?[*:0]const u8,
    };

    /// The strings in `hints` do not need to live as long as `self` after this, since the memory is copied by X11.
    pub fn setClassHints(self: *Self, hints: *const ClassHints) void {
        // Crazy shenanigans so this can make sense.
        // Does this have undefined behavior? I have no damn idea.
        var hint_translation = c.XClassHint{
            .res_name = violateConstCast([*c]u8, @ptrCast([*c]const u8, hints.name)),
            .res_class = violateConstCast([*c]u8, @ptrCast([*c]const u8, hints.class)),
        };

        std.debug.assert(c.XSetClassHint(self.display.ptr, self.window_id, &hint_translation) == 1);
    }

    pub const InputEventMask = c_long;

    pub fn selectInput(self: *Self, events: InputEventMask) void {
        // TODO: turn `events` into a packed struct
        std.debug.assert(c.XSelectInput(self.display.ptr, self.window_id, events) == 1);
    }

    pub fn setWindowBorderColor(self: *Self, color: *const Color) void {
        std.debug.assert(c.XSetWindowBorder(self.display.ptr, self.window_id, color.pixel()) == 1);
    }
};

pub const ResourceManager = struct {
    database: c.XrmDatabase,

    const Self = @This();

    pub const InitError = error{NoXrmString};

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

    // TODO: pub fn getResource(self: *const Self, resource_name: [:0]const u8) ?Resource {}
    // TODO: pub fn setResource(self: *Self, resource_name: [:0]const u8, resource: Resource) SetResourceError!void {}
};

pub const Color = struct {
    const Self = @This();

    color: c.XftColor,

    pub const ParseError = error{CouldNotAllocateColor};

    pub fn init(
        string: [*:0]const u8,
        display: *const Display,
        screen_id: ScreenID,
    ) ParseError!Self {
        var self = Self{ .color = undefined };

        // FIXME: verify if this usage of XftColorAllocName is right
        return if (c.XftColorAllocName(
            display.ptr,
            c.zmenu_defaultvisual(display.ptr, screen_id),
            c.zmenu_defaultcolormap(display.ptr, screen_id),
            string,
            &self.color,
        ) == 0)
            InitError.CouldNotAllocateColor
        else
            self;
    }

    pub fn deinit(self: *Self) void { // FIXME: is this even being used?
        c.XftColorFree(&self.color); // FIXME: not sure if this is right either
    }

    pub fn pixel(self: *const Self) c_ulong {
        return self.color.pixel;
    }
};

pub const Font = struct {
    const Self = @This();

    display_ptr: *const Display,
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

    pub fn init(resource: FontResource, window: *const Window) Error!Self {
        var pattern: ?*c.FcPattern = null;

        const font = switch (resource) {
            .Name => |name| blk: {
                const xft_font = c.XftFontOpenName(
                    window.display.ptr,
                    window.screen_id,
                    name,
                ) orelse return Error.CouldNotLoadFont;
                errdefer c.XftFontClose(window.display.ptr, xft_font);

                // There's a pattern pointer at `xft_font.*.pattern` but it doesn't necessarily yield the same results
                // as the ones FcNameParse does.
                //
                // Accessing by the pointer in the font might result in some missing-character rectangles being drawn.
                //
                // FIXME: is this related to fallback fonts?
                pattern = c.FcNameParse(name) orelse return Error.CouldNotParseFontName;

                break :blk xft_font;
            },
            .Pattern => |patt| c.XftFontOpenPattern(window.display.ptr, patt) orelse return Error.CouldNotLoadFont,
        };
        errdefer c.XftFontClose(window.display.ptr, font);

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
            .display_ptr = window.display.ptr,
            .pattern = pattern,
            .font = font,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.pattern) |patt|
            c.FcPatternDestroy(patt);

        c.XftFontClose(self.display_ptr, self.font);
    }

    pub fn height(self: *const Self) usize {
        return @intCast(usize, self.font.*.ascent + self.font.*.descent);
    }
};

pub const Fontset = struct {
    const Self = @This();

    fonts: ArrayList(Font),
    allocator: *Allocator,

    pub const Error = Font.Error || error{NoFont};

    pub fn init(
        font_names: []const [:0]const u8,
        allocator: *Allocator,
        window: *const Window,
    ) (Error || Allocator.Error)!Self {
        var fonts = ArrayList(Font).init(allocator);
        errdefer {
            for (fonts.items) |*font| font.deinit();
            fonts.deinit();
        }

        for (font_names) |fname| { // TODO: reserve at least a little bit of space
            var font = Font.init(.{ .Name = fname }, window) catch |err| switch (err) {
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

pub const input_events = struct {
    pub const focus_change = c.FocusChangeMask;
    pub const substructure_notify = c.SubstructureNotifyMask;
};

pub const internal = struct {
    pub fn freeResource(resource: *c_void) void {
        // XFree seems to always return 1. It doesn't even seem to throw any X error.
        std.debug.assert(c.XFree(resource) == 1);
    }

    pub fn freePixmap(display: *Display, pixmap: PixmapID) void {
        std.debug.assert(c.XFreePixmap(display.ptr, pixmap) == 1);
    }

    pub fn freeGraphicalContext(display: *Display, pixmap: GraphicalContext) void {
        std.debug.assert(c.XFreeGC(display.ptr, pixmap) == 1);
    }
};

fn violateConstCast(comptime UnderlyingType: type, ptr: *const UnderlyingType) *UnderlyingType {
    return @intToPtr(UnderlyingType, @ptrToInt(ptr));
}
