//! General data structure declarations.
//!
//! I'm not sure where I would put it, so I put them here.

const std = @import("std");
const Allocator = std.mem.Allocator;

const xorg = @import("apis/xorg.zig");
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
        const fg = Color.parse(ss.fg, display, screen_id) catch |err| {
            if (print_error) {
                std.debug.print("Failed to allocate foreground color: {s}\n", .{ss.fg});
            }
            return err;
        };

        const bg = Color.parse(ss.bg, display, screen_id) catch |err| {
            if (print_error) {
                std.debug.print("Failed to allocate background color: {s}\n", .{ss.bg});
            }
            return err;
        };

        return Self{
            .fg = fg,
            .bg = bg,
        };
    }

    pub fn deinit(self: *Self) void {
        self.fg.deinit();
        self.bg.deinit();
    }
};

pub const BaseConfig = struct {
    const Self = @This();

    /// The position/alignment of the menu on the screen.
    position: union(enum) {
        Top: void,
        Bottom: void,
        Centered: void,
    },

    /// Whether fuzzy finding is enabled.
    fuzzy: bool,

    /// Whether case sensitivity is enabled.
    case_sensitive: bool,

    /// The amount of lines.
    lines: usize,

    prompt: ?[:0]const u8,

    default_resources: Resources,

    word_delimeters: []const u8,

    border_width: usize,

    grab_kb: enum { Early, Late },
};

pub const FinalConfig = struct {
    const Self = @This();

    base: *BaseConfig,

    parent_window_id: ?u64,
    monitor_id: ?u32,
    is_embed: bool,

    main_font: ?[:0]const u8,
};
