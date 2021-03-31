const std = @import("std");
const testing = std.testing;

const c = @import("bindings.zig");

/// The underlying type for the display.
///
/// TODO: better doc for this shit
pub const InternalDisplay = c.Display;

/// TODO: doc
pub const Display = struct {
    /// An inner pointer to the X display struct.
    /// This struct is responsible for closing this display, when calling the `deinit()` method.
    _ptr: *InternalDisplay,

    const Self = @This();
    pub const OpenError = error{FailedToOpenDisplay};

    /// Initialize the display.
    pub fn init(display_name: ?[:0]const u8) OpenError!Self {
        return Self{
            ._ptr = c.XOpenDisplay(display_name orelse null) orelse return OpenError.FailedToOpenDisplay,
        };
    }

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

    const d_ref = display.asRef();
}

/// Most actions related to this display on this API are done via this, since many structs might take pointers to a
/// display and relying on a pointer to a malloc'd pointer makes the risk of dangling pointers higher (imo).
///
/// TODO: adjust doc
pub const DisplayRef = struct {
    /// An inner pointer to the X display struct.
    /// This struct is not responsible for closing this display.
    _ptr: *InternalDisplay,

    const Self = @This();

    /// Get the default screen ID of this display.
    pub fn defaultScreenID(self: *const Self) ScreenID {
        return c.x11_defaultscreen(self._ptr);
    }

    /// Get a reference to the default screen of this display, packed with a reference to this display.
    pub fn defaultScreen(self: *Self) ScreenRef {
        return ScreenRef{
            ._display_ptr = self._ptr,
            ._screen_id = self.defaultScreenID(),
        };
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

/// TODO: doc
pub const ScreenRef = struct {
    /// TODO: doc
    _display_ptr: *InternalDisplay,
    /// TODO: doc
    _screen_id: ScreenID,

    const Self = @This();

    /// Get the ID of this screen's root window.
    pub fn rootWindowID(self: *const Self) WindowID {
        return c.x11_rootwindow(self._display_ptr, self._screen_id);
    }

    /// Get a reference to this screen's root window.
    ///
    /// The struct returned by this function may live longer than `self` (and its parent `DisplayRef`), but it may not
    /// live longer than the base `Display`.
    pub fn rootWindow(self: *Self) WindowRef {
        return WindowRef{
            ._display_ptr = self._display_ptr,
            ._screen_id = self._screen_id,
            ._window_id = self.rootWindowID(),
        };
    }
};

test "get the root window of a display" {
    var display = try Display.init(null);
    defer display.deinit();

    var screen = display.asRef().defaultScreen();

    testing.expect(screen.rootWindow()._window_id == screen.rootWindowID());
}

/// The ID of an X Window.
///
/// For a nicer API, WindowRef can be used instead of this, just like ScreenRef can be used instead of ScreenID.
pub const WindowID = c.Window;

/// TODO: doc
pub const WindowRef = struct {
    /// TODO: doc
    _display_ptr: *InternalDisplay,
    /// TODO: doc
    _screen_id: ScreenID,
    /// TODO: doc
    _window_id: WindowID,
};
