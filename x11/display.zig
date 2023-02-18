const std = @import("std");
const testing = std.testing;

const x11 = @import("x11.zig");
const c = @import("bindings.zig");

pub const Event = c.XEvent;

/// Definitions optained from X.h
pub const event_types = struct {
    pub const key_press = c.KeyPress;
    pub const key_release = c.KeyRelease;
    pub const button_press = c.ButtonPress;
    pub const button_release = c.ButtonRelease;
    pub const motion_notify = c.MotionNotify;
    pub const enter_notify = c.EnterNotify;
    pub const leave_notify = c.LeaveNotify;
    pub const focus_in = c.FocusIn;
    pub const focus_out = c.FocusOut;
    pub const keymap_notify = c.KeymapNotify;
    pub const expose = c.Expose;
    pub const graphics_expose = c.GraphicsExpose;
    pub const no_expose = c.NoExpose;
    pub const visibility_notify = c.VisibilityNotify;
    pub const create_notify = c.CreateNotify;
    pub const destroy_notify = c.DestroyNotify;
    pub const unmap_notify = c.UnmapNotify;
    pub const map_notify = c.MapNotify;
    pub const map_request = c.MapRequest;
    pub const reparent_notify = c.ReparentNotify;
    pub const configure_notify = c.ConfigureNotify;
    pub const configure_request = c.ConfigureRequest;
    pub const gravity_notify = c.GravityNotify;
    pub const resize_request = c.ResizeRequest;
    pub const circulate_notify = c.CirculateNotify;
    pub const circulate_request = c.CirculateRequest;
    pub const property_notify = c.PropertyNotify;
    pub const selection_clear = c.SelectionClear;
    pub const selection_request = c.SelectionRequest;
    pub const selection_notify = c.SelectionNotify;
    pub const colormap_notify = c.ColormapNotify;
    pub const client_message = c.ClientMessage;
    pub const mapping_notify = c.MappingNotify;
    pub const generic_event = c.GenericEvent;
    pub const last_event = c.LASTEvent;
};

/// TODO: doc
pub const EventIterator = struct {
    /// TODO: doc
    _display_ptr: *InternalDisplay,

    const Self = @This();

    pub fn next(self: *Self) ?Event {
        var ev: Event = undefined;
        _ = c.XNextEvent(self._display_ptr, &ev);

        return ev;
    }
};

const gmath = @import("gmath");
const Rect2 = gmath.Rect2;

/// The internal X display struct.
///
/// Direct use to this should be avoided when possible, using instead structs like `Display` and `DisplayRef`.
pub const InternalDisplay = c.Display;

/// A wrapper for `InternalDisplay` using idiomatic Zig to initialize and deinitialize the display.
pub const Display = struct {
    /// An inner pointer to the X display struct.
    /// This struct is responsible for closing this display, when calling the `deinit()` method.
    _ptr: *InternalDisplay,

    const Self = @This();
    pub const OpenError = error{FailedToOpenDisplay};

    /// Initialize the display.
    ///
    /// `display_name` is the name of the display. If nothing is provided, X will use the value of the `DISPLAY`
    /// environment variable, which is set at the start of an X server.
    pub fn init(display_name: ?[:0]const u8) OpenError!Self {
        return Self{
            ._ptr = c.XOpenDisplay(
                if (display_name) |d| d.ptr else 0
            ) orelse return OpenError.FailedToOpenDisplay,
        };
    }

    /// Deinitialize the display.
    pub fn deinit(self: *Self) void {
        // XCloseDisplay actually returns a c_int but as far as I've read it is always zero.
        // https://github.com/mirror/libX11/blob/master/src/ClDisplay.c#L73
        std.debug.assert(c.XCloseDisplay(self._ptr) == 0);
    }

    /// Get a pseudo-reference to this display, using the DisplayRef.
    ///
    /// As expected, the struct returned by this function should not live longer than `self`.
    ///
    /// Refer to DisplayRef's documentation for more details.
    pub fn asRef(self: *Self) DisplayRef {
        return DisplayRef{ ._ptr = self._ptr };
    }
};

test "open and close display" {
    var display = try Display.init(null);
    defer display.deinit();
}

test "get display ref" {
    var display = try Display.init(null);
    defer display.deinit();

    _ = display.asRef();
}

/// A reference to a display.
///
/// Most actions related to displays on this API are done via this struct, since we can add methods and, at the same
/// time, get rid of the issue where, since other structs might get references to displays, we can simply pass this
/// DisplayRef as a value and it can get the inner types.
pub const DisplayRef = struct {
    /// An inner pointer to the X display struct.
    /// This struct is not responsible for closing this display.
    _ptr: *InternalDisplay,

    const Self = @This();

    /// Get a reference to the default screen of this display, packed with a reference to this display.
    pub fn defaultScreen(self: Self) ScreenRef {
        return ScreenRef{
            ._display_ptr = self._ptr,
            ._screen_id = self.defaultScreenID(),
        };
    }

    /// Get the default screen ID of this display.
    pub fn defaultScreenID(self: Self) ScreenID {
        return c.x11_defaultscreen(self._ptr);
    }

    /// TODO: doc
    ///
    /// The user is responsible for deciding whether this screen ID is valid.
    pub fn withScreenID(self: Self, screen_id: ScreenID) ScreenRef {
        return ScreenRef{
            ._display_ptr = self._ptr,
            ._screen_id = screen_id,
        };
    }

    /// TODO: doc
    pub fn eventIterator(self: Self) EventIterator {
        return EventIterator{ ._display_ptr = self._ptr };
    }
};

test "get the default screen of a display" {
    var display = try Display.init(null);
    defer display.deinit();

    var d_ref = display.asRef();

    // ScreenRef
    const scr_ref = d_ref.defaultScreen();
    testing.expect(scr_ref._display_ptr == d_ref._ptr);

    // ScreenID
    const scr_id = d_ref.defaultScreenID();
    testing.expect(scr_ref._screen_id == scr_id);
}

/// The ID of an X Screen.
///
/// For a nicer API, ScreenRef can be used instead of this, at the cost of copying some extra pointers, if optimizations
/// don't apply.
pub const ScreenID = c_int;

/// A reference to a screen, plus its parent display.
///
/// This struct is to `ScreenID` what `DisplayRef` is to `Display` (or `InternalDisplay`).
pub const ScreenRef = struct {
    /// A pointer to the internal display pointer.
    ///
    /// This struct is not responsible for closing this display.
    _display_ptr: *InternalDisplay,
    /// The ID of this screen.
    _screen_id: ScreenID,

    const Self = @This();

    /// Get a reference to this screen's root window.
    ///
    /// The struct returned by this function may live longer than `self` (and its parent `DisplayRef`), but it may not
    /// live longer than the base `Display`.
    pub fn rootWindow(self: Self) WindowRef {
        return WindowRef{
            ._display_ptr = self._display_ptr,
            ._screen_id = self._screen_id,
            ._window_id = self.rootWindowID(),
        };
    }

    /// Get the ID of this screen's root window.
    pub fn rootWindowID(self: Self) WindowID {
        return c.x11_rootwindow(self._display_ptr, self._screen_id);
    }

    /// TODO: doc
    ///
    /// The user is responsible for deciding whether this window ID is valid.
    pub fn withWindowID(self: Self, window_id: WindowID) WindowRef {
        return WindowRef{
            ._display_ptr = self._display_ptr,
            ._screen_id = self._screen_id,
            ._window_id = window_id,
        };
    }
};

test "get the root window of a display" {
    var display = try Display.init(null);
    defer display.deinit();

    var screen = display.asRef().defaultScreen();

    testing.expect(screen.rootWindow()._window_id == screen.rootWindowID());
}

test "arbritrary window and screen" {
    var display = try Display.init(null);
    defer display.deinit();

    _ = display.asRef().withScreenID(undefined).withWindowID(undefined);
}

/// The ID of an X Window.
///
/// For a nicer API, `WindowRef` can be used instead of this, just like `ScreenRef` can be used instead of `ScreenID`.
pub const WindowID = c.Window;

/// A reference to a window, and its parent screen and display.
///
/// This struct is to `WindowID` what `ScreenRef` is to `ScreenID`.
pub const WindowRef = struct {
    /// A pointer to the internal display pointer.
    ///
    /// This struct is not responsible for closing this display.
    _display_ptr: *InternalDisplay,
    /// The ID of this screen.
    _screen_id: ScreenID,
    /// The ID of this window.
    _window_id: WindowID,

    const Self = @This();

    pub const Class = enum(u32) {
        input_output = c.InputOutput,
        input_only = c.InputOnly,
        copy_from_parent = c.CopyFromParent,
    };

    pub fn createSubWindow(
        self: Self,
        geometry: Rect2(i32, u32),
        config: struct {
            border_width: u32 = x11.special.copy_from_parent,
            depth: i32 = x11.special.copy_from_parent,
            class: Class = .copy_from_parent,
            visual: [*c]c.Visual = @intToPtr([*c]c.Visual, x11.special.copy_from_parent), // FIXME: make this better
            attributes: *const SetWindowAttributes = &.{},
        },
    ) ManagedWindowRef {
        var raw_attr = config.attributes.toRawAttr();

        const win_id = c.XCreateWindow(
            self._display_ptr,
            self._window_id,
            @as(c_int, geometry.x),
            @as(c_int, geometry.y),
            @as(c_uint, geometry.w),
            @as(c_uint, geometry.h),
            @as(c_uint, config.border_width),
            @as(c_int, config.depth),
            @enumToInt(config.class),
            config.visual,
            raw_attr.value_mask,
            &raw_attr.attrs,
        );

        return ManagedWindowRef{ .ref = WindowRef{
            ._display_ptr = self._display_ptr,
            ._screen_id = self._screen_id,
            ._window_id = win_id,
        } };
    }

    pub fn mapToScreen(self: Self) void {
        _ = c.XMapWindow(self._display_ptr, self._window_id);
    }
};

pub const RawSetWindowAttributes = c.XSetWindowAttributes;

pub const SetWindowAttributes = struct {
    override_redirect: ?bool = null,
    background_pixel: ?x11.draw.Pixel = null,
    event_mask: ?c_long = null,

    const Self = @This();

    pub const RawAttrPair = struct {
        value_mask: c_ulong,
        attrs: RawSetWindowAttributes,
    };

    pub fn toRawAttr(self: *const Self) RawAttrPair {
        var result = RawAttrPair{
            .value_mask = 0,
            .attrs = undefined,
        };

        if (self.override_redirect) |ovr| {
            result.value_mask |= c.CWOverrideRedirect;
            result.attrs.override_redirect = @boolToInt(ovr);
        }

        if (self.background_pixel) |bp| {
            result.value_mask |= c.CWBackPixel;
            result.attrs.background_pixel = bp._data;
        }

        if (self.event_mask) |em| {
            result.value_mask |= c.CWEventMask;
            result.attrs.event_mask = em;
        }

        return result;
    }
};

pub const ManagedWindowRef = struct {
    ref: WindowRef,

    const Self = @This();

    pub fn deinit(self: Self) void {
        _ = c.XDestroyWindow(self.ref._display_ptr, self.ref._window_id);
    }
};
