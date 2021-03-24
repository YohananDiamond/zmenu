const build_options = @import("build_options");
const user_config = @import("config.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ParseIntError = std.fmt.ParseIntError;
const ReadError = std.os.ReadError;
const File = std.fs.File;
const math = std.math;

const draw = @import("draw.zig");
const Point2 = @import("point.zig").Point2;

const apis = @import("apis.zig");
const c = apis.bindings; // FIXME: stop using this here
const xorg = apis.xorg;
const xinerama = apis.xinerama;

const ResourceManager = xorg.ResourceManager;
const Display = xorg.Display;
const ScreenID = xorg.ScreenID;
const WindowID = xorg.WindowID;
const Fontset = xorg.Fontset;
const WindowTriplet = xorg.WindowTriplet;

const data = @import("data.zig");
const Config = data.Config;
const FinalConfig = data.FinalConfig;
const Resources = data.Resources;
const SchemeSet = data.SchemeSet;
const SchemeColors = data.SchemeColors;

const optparse = @import("optparse.zig");
const getLongOption = optparse.getLongOption;
const getShortOption = optparse.getShortOption;
const isLongOrShort = optparse.isLongOrShort;
const isOption = optparse.isOption;

test "entry point" {
    _ = @import("optparse.zig");
    _ = @import("data.zig");
    _ = @import("point.zig");
    _ = @import("utf8.zig");
    _ = @import("draw.zig");
    _ = @import("apis/xorg.zig");

    _ = std.testing.refAllDecls(@This());
}

pub fn main() anyerror!u8 {
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
    defer _ = gpa.deinit();

    // TODO: refactor this to use std.process.ArgIterator
    const args = try std.process.argsAlloc(&gpa.allocator);
    defer std.process.argsFree(&gpa.allocator, args); // we're only gonna do this at the end of the program, so we can use the arg strings freely on the program.

    const cfg = switch (parseArgs(&user_config.cfg, args)) {
        .NotEnoughArgs => {
            std.debug.print("error: could not get program name (arg #0 missing)\n", .{});
            return 1;
        },
        .Success => |cfg| cfg,
        .ExitSuccess => return 0,
        .ExitFailure => return 1,
    };

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

    const target_win = if (cfg.parent_window) |pw|
        @intCast(WindowID, pw)
    else
        root_triplet.window_id;

    const target_win_attr = xorg.windowAttributes(&display, target_win) orelse {
        std.debug.print("error: could not get attributes of target window ({d} a.k.a. 0x{X})\n", .{ target_win, target_win });
        return 1;
    };

    if (ResourceManager.init(&display)) |*resource_manager| {
        defer resource_manager.deinit();

        // TODO: make it so that Xresources don't necessarily override command-line options
    } else |err| switch (err) {
        error.NoXrmString => {
            std.debug.print("warning: failed to load X resources - using default settings\n", .{});
        },
    }

    var kb_grab_state: enum { NotGrabbed, Embed, Grabbed } = if (cfg.is_embed)
        .Embed
    else
        .NotGrabbed;

    if (kb_grab_state == .NotGrabbed and cfg.grab_kb == .Early and !std.os.isatty(0)) {
        attemptGrabKeyboard(&display, target_win) catch |err| switch (err) {
            error.CouldNotGrabKeyboard => {
                std.debug.print("error: failed to grab keyboard\n", .{});
                return 1;
            },
        };

        kb_grab_state = .Grabbed;
    }

    var lines = ArrayList(ArrayList(u8)).init(&gpa.allocator);
    defer {
        for (lines.items) |*line|
            line.deinit();

        lines.deinit();
    }

    var stdin = std.io.getStdIn();
    readLines(2048, &lines, &gpa.allocator, stdin) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("Failed to allocate memory\n", .{});
            return 1;
        },
        else => {
            std.debug.print("Failed to read from stdin: {}\n", .{err});
            return 1;
        },
    };

    // Remove last empty line, if any
    if (lines.items.len > 0 and lines.items[lines.items.len - 1].items.len == 0) {
        _ = lines.pop();
    }

    if (kb_grab_state == .NotGrabbed and cfg.grab_kb == .Late) {
        attemptGrabKeyboard(&display, target_win) catch |err| switch (err) {
            error.CouldNotGrabKeyboard => {
                std.debug.print("error: failed to grab keyboard\n", .{});
                return 1;
            },
        };
    }

    {
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
                    &@field(cfg.default_resources, name),
                    root_triplet.display,
                    root_triplet.screen_id,
                    true,
                ) catch |err| switch (err) {
                    error.CouldNotAllocateColor => return 1,
                };
            }

            break :blk scm;
        };

        var fontset = try Fontset.init(cfg.default_resources.fonts, &gpa.allocator, &root_triplet); // TODO: consider `main_font`
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
        const line_height = fontset.fonts.items[0].height() + 2; // FIXME: does this handle backup fonts? I'm not even sure if dmenu handles backup fonts...
        const menu_height = (cfg.lines + 1) * line_height;
        const lrpad = fontset.lrpad();

        const prompt_width = switch (cfg.prompt.len) {
            0 => 0,
            else => drawctl.getTextWidth(cfg.prompt) + lrpad - lrpad / 4,
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
            if (xinerama) |xn| xinerama_blk: {
                if (target_win == root_triplet.window_id) {
                    if (xn.queryScreens(root_triplet.display)) |*query| {
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

                        if (cfg.monitor_id) |mon_id| {
                            if (mon_id < monitor_count) {
                                monitor_index = mon_id;
                            } else {
                                // TODO: handle zero monitors (does that even happen?)
                                std.debug.print("error: monitor ID is way too big ({}, max {})\n", .{ mon_id, monitor_count - 1 });
                                return 1;
                            }
                        } else {
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
                                        const intersc_area = intersectionArea(
                                            c_int,
                                            c_int,
                                            .{ .x = win_attr.x, .y = win_attr.y },
                                            .{ .x = win_attr.width, .y = win_attr.height },
                                            &screen,
                                        );

                                        if (intersc_area > dummy_area) {
                                            dummy_area = intersc_area;
                                            monitor_index = i;
                                        }
                                    }
                                }
                            }

                            var dummy_x: c_int = undefined;
                            var dummy_y: c_int = undefined;
                            if (cfg.monitor_id == null and dummy_area == 0 and c.XQueryPointer(
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
                                    if (intersectionArea(
                                        c_int,
                                        c_int,
                                        .{ .x = dummy_x, .y = dummy_y },
                                        .{ .x = 1, .y = 1 },
                                        &screens[i],
                                    ) != 0) {
                                        monitor_index = i;
                                        break;
                                    }
                                }
                            }

                            const this_monitor = screens[monitor_index];

                            break :attrs_blk switch (cfg.position) {
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

            break :attrs_blk switch (cfg.position) {
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

        var set_attr: c.XSetWindowAttributes = undefined;
        set_attr.override_redirect = @boolToInt(true);
        set_attr.background_pixel = schemes.normal.bg.pixel();
        set_attr.event_mask = c.ExposureMask | c.KeyPressMask | c.VisibilityChangeMask;

        const menu_win = c.XCreateWindow(
            root_triplet.display.ptr,
            target_win,
            @intCast(c_int, attrs.menu_x),
            @intCast(c_int, attrs.menu_y),
            @intCast(c_uint, attrs.menu_width),
            @intCast(c_uint, menu_height),
            @intCast(c_uint, cfg.border_width),
            c.CopyFromParent,
            c.CopyFromParent,
            c.CopyFromParent,
            c.CWOverrideRedirect | c.CWBackPixel | c.CWEventMask,
            &set_attr,
        );

        xorg.setWindowBorderColor(root_triplet.display, menu_win, &schemes.sel.bg);

        // Just to be sure...
        const zmenu_name_ref: [:0]const u8 = "zmenu";
        var zmenu_name_alloc: []u8 = try gpa.allocator.alloc(u8, zmenu_name_ref.len + 1);
        defer gpa.allocator.free(zmenu_name_alloc);
        std.mem.copy(u8, zmenu_name_alloc, zmenu_name_ref);
        zmenu_name_alloc[zmenu_name_alloc.len - 1] = 0;

        var hint = xorg.ClassHints{
            .res_name = @ptrCast([*c]u8, zmenu_name_alloc),
            .res_class = @ptrCast([*c]u8, zmenu_name_alloc),
        };

        xorg.setClassHint(root_triplet.display, menu_win, &hint);

        const xim: c.XIM = c.XOpenIM(root_triplet.display.ptr, null, null, null) orelse {
            std.debug.print("error: XOpenIM: could not open input device\n", .{});
            return 1;
        };

        const xic = c.XCreateIC(
            xim,
            c.XNInputStyle,
            c.XIMPreeditNothing | c.XIMStatusNothing,
            c.XNClientWindow,
            menu_win,
            c.XNFocusWindow,
            menu_win,
            @intToPtr([*c]u8, 0),
        );

        _ = c.XMapRaised(root_triplet.display.ptr, menu_win); // FIXME: discard

        if (cfg.is_embed) {
            xorg.selectInput(
                root_triplet.display,
                target_win,
                xorg.input_events.focus_change | xorg.input_events.substructure_notify,
            );

            var dw: WindowID = undefined;
            var w: WindowID = undefined;
            var dws: [*c]WindowID = undefined;
            var du: c_uint = undefined;
            if (c.XQueryTree(root_triplet.display.ptr, target_win, &dw, &w, &dws, &du) != 0) {
                if (dws) |d| {
                    var i: usize = 0;
                    while (i < du and d[i] != menu_win) : (i += 1) {
                        xorg.selectInput(
                            root_triplet.display,
                            d[i],
                            xorg.input_events.focus_change,
                        );
                    }

                    xorg.internal.freeResource(dws);
                }
            }

            attemptGrabFocus(root_triplet.display, menu_win) catch |err| switch (err) {
                error.CouldNotGrabFocus => {
                    std.debug.print("error: could not grab focus\n", .{});
                    return 1;
                },
            };
        }

        const menu_cfg = MenuConfig{
            .size = .{
                .x = @intCast(u32, attrs.menu_width),
                .y = @intCast(u32, menu_height),
            },
            .line_height = @intCast(u32, line_height),
            .prompt_width = @intCast(u32, prompt_width),
            .lrpad = @intCast(u32, lrpad),
        };

        drawctl.resize(menu_cfg.size);
        drawMenu(&drawctl, &schemes, &menu_cfg, &cfg);
    }

    return 0;
}

const help_string =
    \\{0s} [OPTIONS]
    \\  A dmenu rewrite in Zig
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

fn showUsage(program_name: []const u8) void {
    std.debug.print(help_string, .{program_name});
}

const ParseResult = union(enum) {
    NotEnoughArgs: void,
    Success: FinalConfig,
    ExitSuccess: void,
    ExitFailure: void,
};

fn parseArgs(base: *const Config, args: []const [:0]const u8) ParseResult {
    const program_name = if (args.len > 0)
        args[0]
    else
        return .NotEnoughArgs;

    var position: ?Config.MenuPosition = null;
    var fuzzy: ?bool = null;
    var case_sensitive: ?bool = null;
    var lines: ?usize = null;
    var default_resources: ?Resources = null;
    var word_delimeters: ?[]const u8 = null;
    var border_width: ?usize = null;
    var grab_kb: ?Config.KeyboardGrab = null;
    var prompt: ?[:0]const u8 = null;
    var parent_window: ?WindowID = null;
    var monitor_id: ?u32 = null;
    var is_embed: bool = false;
    var main_font: ?[:0]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (isLongOrShort(arg, "version", "v")) {
            std.debug.print("zmenu-unknown\n", .{});
            return .ExitSuccess;
        } else if (isLongOrShort(arg, "help", "h")) {
            showUsage(program_name);
            return .ExitSuccess;
        } else if (isLongOrShort(arg, "bottom", "b")) {
            if (position) |_| {
                std.debug.print("error: position argument already specified\n", .{});
                return .ExitFailure;
            } else {
                position = .Bottom;
            }
        } else if (isLongOrShort(arg, "center", "c")) {
            if (position) |_| {
                std.debug.print("error: position argument already specified\n", .{});
                return .ExitFailure;
            } else {
                position = .Centered;
            }
        } else if (isLongOrShort(arg, "top", "t")) {
            if (position) |_| {
                std.debug.print("error: position argument already specified\n", .{});
                return .ExitFailure;
            } else {
                position = .Top;
            }
        } else if (isLongOrShort(arg, "fuzzy", "f")) {
            if (fuzzy) |_| {
                std.debug.print("error: fuzziness argument already specified\n", .{});
                return .ExitFailure;
            } else {
                fuzzy = true;
            }
        } else if (isLongOrShort(arg, "no-fuzzy", "F")) {
            if (fuzzy) |_| {
                std.debug.print("error: fuzziness argument already specified\n", .{});
                return .ExitFailure;
            } else {
                fuzzy = false;
            }
        } else if (isLongOrShort(arg, "case-insensitive", "i")) {
            if (case_sensitive) |_| {
                std.debug.print("error: case sensitivity argument already specified\n", .{});
                return .ExitFailure;
            } else {
                case_sensitive = false;
            }
        } else if (isLongOrShort(arg, "case-sensitive", "I")) {
            if (case_sensitive) |_| {
                std.debug.print("error: case sensitivity argument already specified\n", .{});
                return .ExitFailure;
            } else {
                case_sensitive = true;
            }
        } else if (isLongOrShort(arg, "early-grab-kb", null)) {
            if (grab_kb) |_| {
                std.debug.print("error: keyboard grab argument already specified\n", .{});
                return .ExitFailure;
            } else {
                grab_kb = .Early;
            }
        } else if (isLongOrShort(arg, "late-grab-kb", null)) {
            if (grab_kb) |_| {
                std.debug.print("error: keyboard grab argument already specified\n", .{});
                return .ExitFailure;
            } else {
                grab_kb = .Late;
            }
        } else if (isLongOrShort(arg, "prompt", "p")) {
            if (i + 1 >= args.len or isOption(args[i + 1])) {
                std.debug.print("Missing positional argument for -p/--prompt\n", .{});
                std.debug.print("Use {s} --help for valid arguments.\n", .{program_name});
                return .ExitFailure;
            } else if (prompt) |_| {
                std.debug.print("error: prompt argument already specified\n", .{});
                return .ExitFailure;
            } else {
                i += 1; // go to positional argument
                prompt = args[i];
            }
        } else if (isLongOrShort(arg, "monitor", "m")) {
            if (i + 1 >= args.len or isOption(args[i + 1])) {
                std.debug.print("Missing positional argument for -m/--monitor\n", .{});
                std.debug.print("Use {s} --help for valid arguments.\n", .{program_name});
                return .ExitFailure;
            } else if (monitor_id) |_| {
                std.debug.print("error: monitor argument already specified\n", .{});
                return .ExitFailure;
            } else {
                i += 1; // go to positional argument
                const pos_arg = args[i];

                monitor_id = std.fmt.parseInt(u32, pos_arg, 0) catch |err| {
                    printParseIntError(pos_arg, err);
                    return .ExitFailure;
                };
            }
        } else if (isLongOrShort(arg, "lines", "l")) {
            if (i + 1 >= args.len or isOption(args[i + 1])) {
                std.debug.print("Missing positional argument for -l/--lines\n", .{});
                std.debug.print("Use {s} --help for valid arguments.\n", .{program_name});
                return .ExitFailure;
            } else if (lines) |_| {
                std.debug.print("error: lines argument already specified\n", .{});
                return .ExitFailure;
            } else {
                i += 1; // go to positional argument
                const pos_arg = args[i];

                lines = std.fmt.parseInt(usize, pos_arg, 0) catch |err| {
                    printParseIntError(pos_arg, err);
                    return .ExitFailure;
                };
            }
        } else if (isLongOrShort(arg, "font", "f")) {
            if (i + 1 >= args.len or isOption(args[i + 1])) {
                std.debug.print("Missing positional argument for -f/--font\n", .{});
                std.debug.print("Use {s} --help for valid arguments.\n", .{program_name});
                return .ExitFailure;
            } else if (main_font) |_| {
                std.debug.print("error: font argument already specified\n", .{});
                return .ExitFailure;
            } else {
                i += 1; // go to positional argument
                main_font = args[i];
            }
        } else if (isLongOrShort(arg, "embed", "e")) {
            if (i + 1 >= args.len or isOption(args[i + 1])) {
                std.debug.print("Missing positional argument for -e/--embed\n", .{});
                std.debug.print("Use {s} --help for valid arguments.\n", .{program_name});
                return .ExitFailure;
            } else if (parent_window) |_| {
                std.debug.print("error: embed argument already specified\n", .{});
                return .ExitFailure;
            } else {
                i += 1; // go to positional argument
                const pos_arg = args[i];
                parent_window = std.fmt.parseInt(u32, pos_arg, 0) catch |err| {
                    printParseIntError(pos_arg, err);
                    return .ExitFailure;
                };
                is_embed = true;
            }
        } else if (getLongOption(arg)) |opt| {
            std.debug.print("Invalid option: --{s}\n", .{arg});
            std.debug.print("Use {s} --help for valid arguments.\n", .{program_name});
            return .ExitFailure;
        } else if (getShortOption(arg)) |opt| {
            std.debug.print("Invalid option: -{s}\n", .{arg});
            std.debug.print("Use {s} --help for valid arguments.\n", .{program_name});
            return .ExitFailure;
        } else {
            std.debug.print("Invalid positional argument: {s}\n", .{arg});
            std.debug.print("Use {s} --help for valid arguments.\n", .{program_name});
            return .ExitFailure;
        }
    }

    return .{
        .Success = FinalConfig{
            .position = position orelse base.position,
            .fuzzy = fuzzy orelse base.fuzzy,
            .case_sensitive = case_sensitive orelse base.case_sensitive,
            .lines = lines orelse base.lines,
            .default_resources = base.default_resources,
            .word_delimeters = base.word_delimeters, // FIXME: customize this with args
            .border_width = base.border_width, // FIXME: option
            .grab_kb = grab_kb orelse base.grab_kb,
            .prompt = prompt orelse base.prompt orelse "",
            .parent_window = parent_window,
            .monitor_id = monitor_id,
            .main_font = main_font, // FIXME: option
            .is_embed = is_embed,
        },
    };
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

/// Read lines from `file` onto `list`, using a temporary buffer of `temp_bufsize` bytes.
///
/// Will use the newline character '\n' as a separator and won't place any of them onto the allocated strings. Won't
/// remove trailing lines.
///
/// Will allocate new strings using `allocator`, if needed. Because of that, it's highly recommended to use the same
/// allocator as the one used for the other strings inside. That does not include the outer list, only the inner lists.
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

const GrabKeyboardError = error{CouldNotGrabKeyboard};

fn attemptGrabKeyboard(display: *xorg.Display, window_id: WindowID) GrabKeyboardError!void {
    // TODO: log on each failed attempt
    const threshold: usize = 1000;

    var i: usize = 0;
    while (i < threshold) : (i += 1) {
        const options = .{
            .owner_events = true,
            .pointer_mode = .Async,
            .keyboard_mode = .Async,
            .time = xorg.current_time,
        };

        if (xorg.grabKeyboard(display, window_id, options)) {
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

const GrabFocusError = error{CouldNotGrabFocus};

fn attemptGrabFocus(display: *Display, window_id: WindowID) GrabFocusError!void {
    // TODO: log on each failed attempt

    const threshold: usize = 100;

    var _discard: c_int = undefined;
    var focused_window: WindowID = undefined;

    var i: usize = 0;
    while (i < threshold) : (i += 1) {
        std.debug.assert(c.XGetInputFocus(display.ptr, &focused_window, &_discard) == 1);

        if (focused_window == window_id) {
            return;
        } else {
            std.debug.assert(c.XSetInputFocus(display.ptr, window_id, c.RevertToParent, c.CurrentTime) == 1);
            std.time.sleep(10_000_000);
        }
    }

    return error.CouldNotGrabFocus;
}

usingnamespace if (xinerama) |xn| struct {
    pub fn intersectionArea(
        comptime PosType: type,
        comptime SizeType: type,
        pos: Point2(PosType),
        size: Point2(SizeType),
        screen_info: *const xn.ScreenInfo, // FIXME: why is this even needed here?
    ) c_int {
        const max = math.max;
        const min = math.min;

        const si = screen_info;
        const part1 = max(0, min(pos.x + size.x, si.x_org + si.width)) - max(pos.x, si.x_org);
        const part2 = max(0, min(pos.y + size.y, si.y_org + si.height)) - max(pos.y, si.y_org);

        return part1 * part2;
    }
} else struct {};

const MenuConfig = struct {
    size: Point2(u32),
    line_height: u32,
    prompt_width: u32,
    lrpad: u32,
};

fn drawMenu(
    drw: *draw.DrawControl,
    schemes: anytype, // FIXME
    menu_config: *const MenuConfig,
    config: *const FinalConfig,
) void {
    // draw menu box
    drw.drawRect(
        .{ .x = 0, .y = 0 },
        menu_config.size,
        .Filled,
        &schemes.sel.bg,
    );

    var x: u32 = 0;

    if (config.prompt.len > 0) {
        x = drw.drawText(
            config.prompt,
            .{ .x = 0, .y = 0 },
            .{ .x = menu_config.prompt_width, .y = menu_config.line_height },
            @divFloor(menu_config.lrpad, 2),
            &schemes.sel.fg,
            &schemes.sel.bg,
        ).text_width;
    }
}
