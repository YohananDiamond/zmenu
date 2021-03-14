pub const has_xinerama: bool = true;

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ParseIntError = std.fmt.ParseIntError;
const ReadError = std.os.ReadError;
const File = std.fs.File;
const math = std.math;

const c = @import("apis/_bindings.zig"); // FIXME: stop using this here
const draw = @import("draw.zig");
const Point2 = @import("point.zig").Point2;
const xorg = @import("apis/xorg.zig");
const xinerama = if (has_xinerama)
    @import("apis/xinerama.zig")
else
    struct {};

const ResourceManager = xorg.ResourceManager;
const Display = xorg.Display;
const ScreenID = xorg.ScreenID;
const WindowID = xorg.WindowID;
const Fontset = xorg.Fontset;
const WindowTriplet = xorg.WindowTriplet;

const api = @import("api.zig");
const BaseConfig = api.BaseConfig;
const FinalConfig = api.FinalConfig;
const Resources = api.Resources;
const SchemeSet = api.SchemeSet;
const SchemeColors = api.SchemeColors;

const user_config = @import("config.zig");
const str = @import("str.zig");

pub const GrabKeyboardError = error{CouldNotGrabKeyboard};

fn attemptGrabKeyboard(display: *const xorg.Display, window_id: WindowID) GrabKeyboardError!void {
    const threshold: usize = 1000;

    var i: usize = 0;
    while (i < threshold) : (i += 1) {
        if (xorg.grabKeyboard(display, window_id)) {
            break;
        } else |err| switch (err) {
            error.CouldNotGrabKeyboard => {
                std.time.sleep(1_000_000);
            },
        }
    } else {
        return error.CouldNotGrabKeyboard;
    }
}

pub fn intersectionArea( // FIXME: proper typing and understand what's going on
    x: anytype,
    y: anytype,
    width: anytype,
    height: anytype,
    dummy_r: anytype, // FIXME: figure out what this does
) c_int {
    return (math.max(0, math.min(x + width, dummy_r.x_org + dummy_r.width) - math.max(x, dummy_r.x_org)) *
        math.max(0, math.min(y + height, dummy_r.y_org + dummy_r.height) - math.max(y, dummy_r.y_org)));
}

pub fn main() anyerror!u8 {
    std.debug.print("Starting...\n", .{}); // FIXME: remove this

    {
        const s = "Hello, World!";
        const utf8 = @import("utf8.zig");

        var i: usize = 0;

        while (i < s.len) {
            const length = utf8.charLength(s[i..]);

            if (length == 0) unreachable; // FIXME

            std.debug.print("{s}\n", .{s[i .. i + length]});

            i += length;
        }
    }

    switch (std.Target.current.os.tag) {
        .linux => {},
        .openbsd => {
            // BSD's `pledge()` syscall makes it so we can restrict what this
            // program can do. This is useful against, for example, unwanted
            // code execution.
            //
            // This program can only work with:
            // `stdio`: I/O streams stuff, sockets and time
            // `rpath`: file and directory read-only access
            //
            // See https://man.openbsd.org/OpenBSD-6.2/pledge.2 for more info.
            const promises = "stdio rpath";

            const result = std.c.pledge(
                promises,
                null, // we're not doing anything with execpromises
            );

            if (result == -1) {
                std.debug.print("Failed to pledge with promises: {s}\n", .{promises});
                return 1;
            }
        },
        else => |tag| @compileError("Unsupported platform: " ++ @tagName(tag)),
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = &gpa.allocator;

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args); // we're only gonna do this at the end of the program, so we can use the arg strings freely on the program.

    var base_cfg = user_config.cfg;
    var final_cfg = FinalConfig{
        .base = &base_cfg,
        .parent_window_id = null,
        .monitor_id = null,
        .main_font = null,
        .is_embed = false,
    };
    switch (updateConfigFromArgs(&final_cfg, args)) {
        .NotEnoughArgs => {
            std.debug.print("error: not enough args (not even the program name!)\n", .{});
            return 1;
        },
        .Success => {},
        .ExitSuccess => return 0,
        .ExitFailure => return 1,
    }

    if (!xorg.hasLocaleSupport()) {
        std.debug.print("warning: no locale support\n", .{});
    }

    var display = Display.init() catch |err| switch (err) {
        error.OpenDisplayError => {
            std.debug.print("error: could not open display\n", .{});
            return 1;
        },
    };
    defer display.deinit();

    const root_triplet = blk: {
        const screen_id = xorg.defaultScreenID(&display);

        break :blk WindowTriplet{
            .display = &display,
            .screen_id = screen_id,
            .window_id = xorg.rootWindowID(&display, screen_id),
        };
    };

    const target_win = @intCast(WindowID, final_cfg.parent_window_id orelse root_triplet.window_id);
    const target_win_attr = xorg.windowAttributes(&display, target_win) orelse {
        std.debug.print("error: could not get attributes of target window ({d} a.k.a. 0x{X})\n", .{ target_win, target_win });
        return 1;
    };

    if (ResourceManager.init(&display)) |*resource_manager| {
        defer resource_manager.deinit();

        // TODO: make it so that Xresources don't necessarily override command-line options
    } else |err| switch (err) {
        ResourceManager.InitError.NoXrmString => {
            std.debug.print("warning: failed to load X resources - using default settings\n", .{});
        },
    }

    var keyboard_grabbed = false;

    if (final_cfg.base.grab_kb == .Early and !std.os.isatty(0)) {
        if (!final_cfg.is_embed)
            attemptGrabKeyboard(&display, target_win) catch |err| switch (err) {
                error.CouldNotGrabKeyboard => {
                    std.debug.print("error: failed to grab keyboard\n", .{});
                    return 1;
                },
            };
        keyboard_grabbed = true;
    }

    var lines = ArrayList(ArrayList(u8)).init(alloc);
    defer {
        for (lines.items) |*line|
            line.deinit();

        lines.deinit();
    }

    var stdin = std.io.getStdIn();
    readLines(2048, &lines, alloc, stdin) catch |err| {
        std.debug.print("Failed to read from stdin: {}\n", .{err});
        return 1;
    };

    // Remove last empty line, if any
    if (lines.items.len > 0 and lines.items[lines.items.len - 1].items.len == 0) {
        _ = lines.pop();
    }

    if (!keyboard_grabbed and !final_cfg.is_embed) {
        attemptGrabKeyboard(&display, target_win) catch |err| switch (err) {
            error.CouldNotGrabKeyboard => {
                std.debug.print("error: failed to grab keyboard\n", .{});
                return 1;
            },
        };
    }

    {
        const resources_ptr: *const Resources = &final_cfg.base.default_resources;

        const schemes = blk: {
            var scm: SchemeSet = undefined;

            const fields = &[_][]const u8{
                "normal",
                "normal_highlight",
                "sel",
                "sel_highlight",
                "out",
            };

            inline for (fields) |name| {
                @field(scm, name) = SchemeColors.initFromSchemeStrings(
                    &@field(resources_ptr, name),
                    root_triplet.display,
                    root_triplet.screen_id,
                    true,
                ) catch |err| switch (err) {
                    error.CouldNotAllocateColor => return 1,
                };
            }

            break :blk scm;
        };

        var fontset = try Fontset.init(resources_ptr.fonts, alloc, &root_triplet); // TODO: consider `main_font`
        defer fontset.deinit();

        var drawctl = draw.DrawControl.init(
            &root_triplet,
            Point2(u32){
                .x = @intCast(u32, target_win_attr.width),
                .y = @intCast(u32, target_win_attr.height),
            },
            &fontset,
        );
        defer drawctl.deinit();

        // Calculate menu geometry
        const dummy_bh = fontset.fonts.items[0].height() + 2; // FIXME: does this handle backup fonts? I'm not even sure if dmenu handles backup fonts...
        const menu_height = (final_cfg.base.lines + 1) * dummy_bh;
        const prompt = final_cfg.base.prompt orelse "";
        const lrpad = fontset.lrpad();

        const prompt_width = switch (prompt.len) {
            0 => 0,
            else => drawctl.getTextWidth(prompt) + lrpad - lrpad / 4,
        };

        const max_text_width = blk: {
            var v: usize = 0;
            for (lines.items) |line| {
                v = math.max(drawctl.getTextWidth(line.items), v);
            }

            break :blk v;
        };

        const AttrsBlk = struct {
            menu_width: usize,
            menu_x: isize,
            menu_y: isize,
        };

        var monitor_index: usize = 0;

        const attrs: AttrsBlk = attrs_blk: {
            if (has_xinerama) xinerama_blk: {
                if (target_win == root_triplet.window_id) {
                    if (xinerama.queryScreens(root_triplet.display)) |*query| {
                        defer query.deinit();
                        const screens = query.screens;
                        const monitor_count = screens.len;

                        var dummy_w: WindowID = undefined;
                        var dummy_di: c_int = undefined;
                        var dummy_area: c_int = 0;
                        var dummy_pw: WindowID = undefined;

                        // From documentation:
                        //
                        // The XGetInputFocus function returns the focus window and the current focus state.
                        //
                        // Also, XGetInputFocus seems to always return 1, so let's assert that here.
                        std.debug.assert(c.XGetInputFocus(root_triplet.display.ptr, &dummy_w, &dummy_di) == 1);

                        dummy_label2: {
                            if (final_cfg.monitor_id) |mon_id| {
                                if (mon_id < monitor_count) {
                                    monitor_index = mon_id;
                                    break :dummy_label2;
                                } else {
                                    // TODO: handle zero monitors (does that even happen?)
                                    std.debug.print("error: monitor ID is way too big ({}, max {})\n", .{ mon_id, monitor_count - 1 });
                                    return 1;
                                }
                            }

                            var dummy_dw: WindowID = undefined;
                            var dummy_dws: [*c]WindowID = undefined;
                            var dummy_du: c_uint = undefined;

                            if (dummy_w != root_triplet.window_id and dummy_w != c.PointerRoot and dummy_w != c.None) {
                                // FIXME: dummy comment: find top-level window containing current input focus
                                while (true) {
                                    dummy_pw = dummy_w;
                                    const dummy_result = c.XQueryTree(
                                        root_triplet.display.ptr,
                                        dummy_pw,
                                        &dummy_dw,
                                        &dummy_w,
                                        &dummy_dws,
                                        &dummy_du,
                                    );

                                    if (dummy_result != 0 and dummy_dws != 0) {
                                        xorg.internal.freeResource(dummy_dws);
                                    }

                                    if (dummy_w == root_triplet.window_id or dummy_w == dummy_pw)
                                        break;
                                }

                                // FIXME: dummy comment: find xinerama screen which the window intersects most
                                if (xorg.windowAttributes(root_triplet.display, dummy_pw)) |win_attr| { // FIXME: should errors here be handled this way?
                                    for (screens) |screen, i| {
                                        const intersc_area = intersectionArea(win_attr.x, win_attr.y, win_attr.width, win_attr.height, screen);

                                        if (intersc_area > dummy_area) {
                                            dummy_area = intersc_area;
                                            monitor_index = i;
                                        }
                                    }
                                }
                            }

                            var dummy_x: c_int = undefined;
                            var dummy_y: c_int = undefined;
                            if (final_cfg.monitor_id == null and dummy_area == 0 and c.XQueryPointer(
                                root_triplet.display.ptr,
                                root_triplet.window_id,
                                &dummy_dw,
                                &dummy_dw,
                                &dummy_x,
                                &dummy_y,
                                &dummy_di,
                                &dummy_di,
                                &dummy_du,
                            ) != 0) {
                                // FIXME: dummy comment: no focused window is on screen, so use pointer location instead
                                for (screens) |screen, i| {
                                    if (intersectionArea(dummy_x, dummy_y, 1, 1, screens[i]) != 0) {
                                        monitor_index = i;
                                        break;
                                    }
                                }
                            }

                            const this_monitor = screens[monitor_index];

                            break :attrs_blk switch (final_cfg.base.position) {
                                .Centered => blk: {
                                    const dummy_calc = @floatToInt(usize, @intToFloat(f32, this_monitor.width) / 2.75); // FIXME: what does this mean?
                                    const menu_width: usize = math.min(math.max(max_text_width + prompt_width, dummy_calc), this_monitor.width);

                                    break :blk AttrsBlk{
                                        .menu_width = menu_width,
                                        .menu_x = @intCast(isize, this_monitor.x_org) + @divFloor(@intCast(isize, this_monitor.width) - @intCast(isize, menu_width), 2),
                                        .menu_y = @intCast(isize, this_monitor.y_org) + @divFloor(@intCast(isize, this_monitor.height) - @intCast(isize, menu_height), 2),
                                    };
                                },
                                .Top => AttrsBlk{
                                    .menu_width = @intCast(usize, this_monitor.width),
                                    .menu_x = this_monitor.x_org,
                                    .menu_y = this_monitor.y_org,
                                },
                                .Bottom => AttrsBlk{
                                    .menu_width = @intCast(usize, this_monitor.width),
                                    .menu_x = this_monitor.x_org,
                                    .menu_y = this_monitor.y_org + (this_monitor.height - @intCast(isize, menu_height)),
                                },
                            };
                        }

                        break :xinerama_blk;
                    }
                }
            }

            // FIXME: maybe get window attributes again?
            // if (!XGetWindowAttributes(dpy, parentwin, &wa))
            // 	die("could not get embedding window attributes: 0x%lx",
            // 	    parentwin);

            break :attrs_blk switch (final_cfg.base.position) {
                .Centered => blk: {
                    const menu_width = math.min(math.max(max_text_width + prompt_width, 100), target_win_attr.width);

                    break :blk AttrsBlk{
                        .menu_width = menu_width,
                        .menu_x = @divFloor(@intCast(isize, target_win_attr.width) - @intCast(isize, menu_width), 2),
                        .menu_y = @divFloor(@intCast(isize, target_win_attr.height) - @intCast(isize, menu_height), 2),
                    };
                },
                .Top => AttrsBlk{
                    .menu_width = @intCast(usize, target_win_attr.width),
                    .menu_x = 0,
                    .menu_y = 0,
                },
                .Bottom => AttrsBlk{
                    .menu_width = @intCast(usize, target_win_attr.width),
                    .menu_x = 0,
                    .menu_y = @intCast(isize, target_win_attr.height) - @intCast(isize, menu_height),
                },
            };
        };

        // var attr: c.SetWindowAttributes = undefined;
        // const hint = c.XClassHint{
        //     .res_name = "zmenu",
        //     .res_class = "zmenu",
        // };
    }

    return 0;
}

fn showUsage(progname: []const u8) void {
    // TODO: option to print item index on list instead of string
    const help_string =
        \\{0s} [OPTIONS]
        \\  A dmenu rewrite in Zig
        \\
        \\General options:
        \\  -h, --help: show this message and exit
        \\  -v, --version: show version information and exit
        \\  -l, --lines <AMOUNT>: set the amount of lines to be showed
        \\  -p, --prompt <PROMPT>: specify the prompt to be used
        \\  --font <FONT>: specify the font ID
        \\  -m, --monitor <ID>: specify the ID of the monitor where the menu window will be shown
        \\  -e, --embed <ID>: specify a window to embed the menu onto
        \\
        \\Position options:
        \\  -b, --bottom: position the menu on the bottom of the screen
        \\  -t, --top: position the menu on the top of the screen
        \\  -c, --center: position the menu on the center of the screen
        \\
        \\Fuzzy matching options:
        \\  -f, --fuzzy: enable fuzzy matching
        \\  -F, --no-fuzzy: disable fuzzy matching
        \\
        \\Case sensitivity options:
        \\  -i, --case-insensitive: disable case sensitivity matching
        \\  -I, --case-sensitive: enable case sensitivity matching
        \\
        \\Keyboard grabbing options:
        \\  At some point of its execution, {0s} grabs the keyboard so the user can select stuff.
        \\  These options can be used to specify when the keyboard is grabbed.
        \\  --grab-kb: grab the keyboard as soon as possible, before stdin is closed. This option is ignored if stdin is a TTY.
        \\  --no-grab-kb: don't grab the keyboard until stdin is closed.
    ;

    std.debug.print(help_string, .{progname});
}

pub const ArgParseResult = enum {
    NotEnoughArgs,
    Success,
    ExitSuccess,
    ExitFailure,
};

fn updateConfigFromArgs(cfg: *FinalConfig, args: []const [:0]const u8) ArgParseResult {
    const progname = if (args.len > 0)
        args[0]
    else
        return .NotEnoughArgs;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (isLongOrShort(arg, "version", "v")) {
            std.debug.print("zmenu-unknown\n", .{});
            return .ExitSuccess;
        } else if (isLongOrShort(arg, "help", "h")) {
            showUsage(progname);
            return .ExitSuccess;
        } else if (isLongOrShort(arg, "bottom", "b")) {
            cfg.base.position = .Bottom;
        } else if (isLongOrShort(arg, "center", "c")) {
            cfg.base.position = .Centered;
        } else if (isLongOrShort(arg, "top", "t")) {
            cfg.base.position = .Top;
        } else if (isLongOrShort(arg, "fuzzy", "f")) {
            cfg.base.fuzzy = true;
        } else if (isLongOrShort(arg, "no-fuzzy", "F")) {
            cfg.base.fuzzy = false;
        } else if (isLongOrShort(arg, "case-insensitive", "i")) {
            cfg.base.case_sensitive = false;
        } else if (isLongOrShort(arg, "case-sensitive", "I")) {
            cfg.base.case_sensitive = true;
        } else if (isLongOrShort(arg, "early-grab-kb", null)) {
            cfg.base.grab_kb = .Early;
        } else if (isLongOrShort(arg, "late-grab-kb", null)) {
            cfg.base.grab_kb = .Late;
        } else if (isLongOrShort(arg, "prompt", "p")) {
            if (i + 1 >= args.len or isOption(args[i + 1])) {
                std.debug.print("Missing positional argument for -p/--prompt\n", .{});
                std.debug.print("Use {s} --help for valid arguments.\n", .{progname});
                return .ExitFailure;
            }

            i += 1; // go to positional argument
            cfg.base.prompt = args[i];
        } else if (isLongOrShort(arg, "monitor", "m")) {
            if (i + 1 >= args.len or isOption(args[i + 1])) {
                std.debug.print("Missing positional argument for -m/--monitor\n", .{});
                std.debug.print("Use {s} --help for valid arguments.\n", .{progname});
                return .ExitFailure;
            }

            i += 1; // go to positional argument
            const pos_arg = args[i];
            cfg.monitor_id = std.fmt.parseInt(u32, pos_arg, 0) catch |err| {
                printParseIntError(pos_arg, err);
                return .ExitFailure;
            };

            // TODO: figure out what the `mon` var means on dmenu
        } else if (isLongOrShort(arg, "lines", "l")) {
            if (i + 1 >= args.len or isOption(args[i + 1])) {
                std.debug.print("Missing positional argument for -l/--lines\n", .{});
                std.debug.print("Use {s} --help for valid arguments.\n", .{progname});
                return .ExitFailure;
            }

            i += 1; // go to positional argument
            const pos_arg = args[i];
            cfg.base.lines = std.fmt.parseInt(usize, pos_arg, 0) catch |err| {
                printParseIntError(pos_arg, err);
                return .ExitFailure;
            };
        } else if (isLongOrShort(arg, "font", "f")) {
            if (i + 1 >= args.len or isOption(args[i + 1])) {
                std.debug.print("Missing positional argument for -f/--font\n", .{});
                std.debug.print("Use {s} --help for valid arguments.\n", .{progname});
                return .ExitFailure;
            }

            i += 1; // go to positional argument
            cfg.main_font = args[i];
        } else if (isLongOrShort(arg, "embed", "e")) {
            if (i + 1 >= args.len or isOption(args[i + 1])) {
                std.debug.print("Missing positional argument for -e/--embed\n", .{});
                std.debug.print("Use {s} --help for valid arguments.\n", .{progname});
                return .ExitFailure;
            }

            i += 1; // go to positional argument
            const pos_arg = args[i];

            cfg.is_embed = true;

            cfg.parent_window_id = std.fmt.parseInt(u32, pos_arg, 0) catch |err| {
                printParseIntError(pos_arg, err);
                return .ExitFailure;
            };
        } else if (getLongOption(arg)) |opt| {
            std.debug.print("Invalid option: --{s}\n", .{arg});
            std.debug.print("Use {s} --help for valid arguments.\n", .{progname)};
            return .ExitFailure;
        } else if (getShortOption(arg)) |opt| {
            std.debug.print("Invalid option: -{s}\n", .{arg});
            std.debug.print("Use {s} --help for valid arguments.\n", .{progname)};
            return .ExitFailure;
        } else {
            std.debug.print("Invalid positional argument: {s}\n", .{arg});
            std.debug.print("Use {s} --help for valid arguments.\n", .{progname)};
            return .ExitFailure;
        }
    }

    return .Success;
}

fn getLongOption(string: [:0]const u8) ?[:0]const u8 { // TODO: make this "generic" over slice types
    return if (string[0] == '-' and string[1] == '-') string[2..] else null;
}

fn getShortOption(string: [:0]const u8) ?[:0]const u8 { // TODO: make this "generic" over slice types
    return if (string[0] == '-' and string[1] != '-') string[1..] else null;
}

fn isOption(string: [:0]const u8) bool {
    return string[0] == '-';
}

fn getPositionalOption(string: [:0]const u8) ?[:0]const u8 { // TODO: make this "generic" over slice types
    return if (string[0] != '-') string else null;
}

fn isLongOrShort(string: [:0]const u8, long: ?[:0]const u8, short: ?[:0]const u8) bool {
    if (getLongOption(string)) |opt| {
        return if (long) |long_|
            str.equals(opt, long_, .{})
        else
            false;
    } else if (getShortOption(string)) |opt| {
        return if (short) |short_|
            str.equals(opt, short_, .{})
        else
            false;
    } else {
        return false;
    }
}

fn printParseIntError(string: []const u8, err: ParseIntError) void {
    const error_msg: []const u8 = switch (err) {
        ParseIntError.Overflow => "overflow encountered (number too big / small)",
        ParseIntError.InvalidCharacter => "invalid character encountered",
    };

    std.debug.print("Failed to parse number \"{s}\": {s}", .{
        string,
        error_msg,
    });
}

/// Read lines from `file` onto `list`, using a temporary buffer of `bufsize`
/// bytes.
///
/// Will use the newline character '\n' as a separator and won't place
/// any of them onto the allocated strings. Won't remove trailing lines.
///
/// Will allocate new strings using `allocator`, if needed. Because of that,
/// it's recommended to use the same allocator as the one used for the other
/// strings inside. That does not include the outer list, only the inner lists.
fn readLines(
    comptime temp_bufsize: usize,
    list: *ArrayList(ArrayList(u8)),
    string_allocator: *Allocator,
    file: File,
) (ReadError || Allocator.Error)!void {
    var buf: [temp_bufsize]u8 = undefined;
    var first_split = false;

    while (true) {
        const chars_read = try file.read(&buf);

        if (chars_read == 0) return;

        var split = std.mem.split(buf[0..chars_read], "\n");

        if (split.next()) |line| {
            if (first_split or list.items.len == 0) {
                var string = ArrayList(u8).init(string_allocator);
                try string.appendSlice(line);
                try list.append(string);
            } else {
                try list.items[list.items.len - 1].appendSlice(line);
            }
        }

        while (split.next()) |line| {
            var string = ArrayList(u8).init(string_allocator);
            try string.appendSlice(line);
            try list.append(string);
        }
    }
}

test {
    _ = @import("str.zig");
}
