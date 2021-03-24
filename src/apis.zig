const build_options = @import("build_options");

pub const xorg = @import("apis/xorg.zig");

pub const xinerama: ?type = if (build_options.use_xinerama)
    @import("apis/xinerama.zig")
else
    null;

pub const bindings = @import("apis/_bindings.zig");
