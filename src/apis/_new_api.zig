const c = @compileError("TODO: import stuff");

pub const Connection = struct {
    _ptr: *c.Display,

    const Self = @This();

    pub fn init() Self {
        unreachable;
    }

    pub fn initWithDisplay(display: [*:0]const u8) Self {
        unreachable;
    }

    pub fn deinit(self: *Self) void {}
};
