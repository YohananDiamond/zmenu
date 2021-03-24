const build_options = @import("build_options");

pub usingnamespace @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xft/Xft.h");
    @cInclude("X11/Xresource.h");
    @cInclude("locale.h");

    @cInclude("zmenu_xlib.h");

    if (build_options.use_xinerama) {
        @cInclude("X11/extensions/Xinerama.h");
    }
});
