//! General data structure declarations.
//!
//! I'm not sure where I would put it, so I put them here.

const std = @import("std");
const Allocator = std.mem.Allocator;

const apis = @import("apis.zig");
const xorg = apis.xorg;
const Display = xorg.Display;
const WindowID = xorg.WindowID;
const Color = xorg.Color;
const ScreenID = xorg.ScreenID;

const str = @import("str.zig");

pub const Resources = struct {
    const Self = @This();

    /// Color schemes
    normal: SchemeStrings,
    normal_highlight: SchemeStrings,
    sel: SchemeStrings,
    sel_highlight: SchemeStrings,
    out: SchemeStrings,

    /// Fonts
    fonts: []const [:0]const u8,
};

pub const SchemeSet = struct {
    normal: SchemeColors,
    normal_highlight: SchemeColors,
    sel: SchemeColors,
    sel_highlight: SchemeColors,
    out: SchemeColors,
};

pub const SchemeStrings = struct {
    fg: [:0]const u8,
    bg: [:0]const u8,
};

pub const SchemeColors = struct {
    const Self = @This();

    fg: Color,
    bg: Color,

    pub fn initFromSchemeStrings(
        ss: *const SchemeStrings,
        display: *const Display,
        screen_id: ScreenID,
        print_error: bool,
    ) error{CouldNotAllocateColor}!Self {
        return Self{
            .fg = Color.parse(ss.fg, display, screen_id) catch |err| {
                if (print_error) {
                    std.debug.print("Failed to allocate foreground color: {s}\n", .{ss.fg});
                }
                return err;
            },
            .bg = Color.parse(ss.bg, display, screen_id) catch |err| {
                if (print_error) {
                    std.debug.print("Failed to allocate background color: {s}\n", .{ss.bg});
                }
                return err;
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.fg.deinit();
        self.bg.deinit();
    }
};

pub const Config = struct {
    /// The position/alignment of the menu on the screen.
    position: MenuPosition,

    /// Whether fuzzy finding is enabled.
    fuzzy: bool,

    /// Whether case sensitivity is enabled.
    case_sensitive: bool,

    /// The amount of lines to show.
    /// TODO: document 0
    lines: usize,

    /// The prompt, if any.
    prompt: ?[:0]const u8,

    /// TODO: doc
    default_resources: *const Resources,

    /// TODO: doc
    word_delimeters: []const u8,

    /// TODO: doc
    border_width: usize,

    /// TODO: doc
    grab_kb: KeyboardGrab,

    /// TODO: doc
    pub const MenuPosition = enum {
        Top,
        Bottom,
        Centered,
    };

    /// TODO: doc
    pub const KeyboardGrab = enum {
        Early,
        Late,
    };
};

pub const FinalConfig = struct {
    /// TODO: doc (forward to Config idk)
    position: Config.MenuPosition,
    fuzzy: bool,
    case_sensitive: bool,
    lines: usize,
    default_resources: *const Resources,
    word_delimeters: []const u8,
    border_width: usize,
    grab_kb: Config.KeyboardGrab,

    /// TODO: doc (with differences)
    prompt: [:0]const u8,

    /// TODO: doc
    parent_window: ?WindowID,

    /// TODO: doc
    monitor_id: ?u32,

    /// TODO: doc
    is_embed: bool,

    /// TODO: doc
    main_font: ?[:0]const u8,
};
