pub usingnamespace @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xft/Xft.h");
    @cInclude("X11/Xresource.h");
    @cInclude("ext_xlib.h");
    @cInclude("ext_misc.h");
    @cInclude("locale.h");

    if (@import("../main.zig").has_xinerama) {
        @cInclude("X11/extensions/Xinerama.h");
    }
});
