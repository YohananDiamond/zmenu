const std = @import("std");
const x11 = @import("x11");

pub fn main() anyerror!void {
    var display = try x11.Display.init(null);
    defer display.deinit();

    var display_ref = display.asRef();
    var draw_ctl = display_ref.drawControl();

    draw_ctl.drawRect(
        Rect(i32){
            .x = 10,
            .y = 10,
            .w = 100,
            .h = 25,
        },
    );

    // TODO: objective I: draw a sample window
}
