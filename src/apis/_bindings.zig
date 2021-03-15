pub usingnamespace @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xft/Xft.h");
    @cInclude("X11/Xresource.h");
    @cInclude("zmenu_xlib.h");
    @cInclude("locale.h");

    if (@import("build_options").use_xinerama) {
        @cInclude("X11/extensions/Xinerama.h");
    }
});
