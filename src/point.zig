pub fn Point2(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        pub fn init(x: T, y: T) callconv(.Inline) Self {
            return Self{ .x = x, .y = y };
        }

        pub fn asArray(self: *const Self) callconv(.Inline) [2]T {
            return [_]T{ self.x, self.y };
        }
    };
}
