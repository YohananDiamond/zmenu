const std = @import("std");

const x11 = @import("x11");
const Pixel = x11.draw.Pixel;
const event_types = x11.display.event_types;

// Objective I: draw two rectangles to a window with two different colors
pub fn main() anyerror!void {
    const ems = x11.event_masks;

    std.debug.print("Opening display...\n", .{});

    var display = try x11.Display.init(null);
    defer display.deinit();

    var display_ref = display.asRef();

    var root_win = display_ref.defaultScreen().rootWindow();

    std.debug.print("Creating window...\n", .{});

    var main_win_m = root_win.createSubWindow(
        .{ .x = 10, .y = 25, .w = 500, .h = 300 },
        .{ .attributes = &.{
            .override_redirect = true,
            .background_pixel = Pixel.fromRGB(0, 0, 0),
            .event_mask = (ems.exposure_mask | ems.key_press_mask | ems.visibility_change_mask),
        } },
    );
    defer main_win_m.deinit();

    const main_win = main_win_m.ref;

    std.debug.print("Creating graphical context...\n", .{});

    var ctl = x11.draw.Context.init(main_win, .{ .x = 500, .y = 300 });
    defer ctl.deinit();

    _ = x11.c.XSelectInput(display_ref._ptr, main_win._window_id, x11.c.ExposureMask | x11.c.KeyPressMask);
    _ = x11.c.XSetStandardProperties(display_ref._ptr, main_win._window_id, "Test", "foo", x11.c.None, null, 0, null);

    main_win.mapToScreen();

    var event_iter: x11.display.EventIterator = display_ref.eventIterator();
    while (event_iter.next()) |event| switch (event.type) {
        event_types.expose => {
            ctl.drawRect(
                .{.x = 10, .y = 10, .w = 50, .h = 50},
                Pixel.fromRGB(150, 150, 15),
                .Filled,
            );

            ctl.drawString("Hello, my name is 256 thousand", .{ .x = 10, .y = 80 });
        },
        else => |t| {
            std.debug.print("Unknown event type: {}\n", .{t});
        },
    };

    std.debug.print("Waiting some time (5s)...\n", .{});

    std.time.sleep(5_000_000_000);
}
