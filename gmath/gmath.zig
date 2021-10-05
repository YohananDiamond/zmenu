pub fn Rect2(comptime PosT: type, comptime SizeT: type) type {
    return struct {
        x: PosT,
        y: PosT,
        w: SizeT,
        h: SizeT,

        const Self = @This();

        pub fn fromPoints(pos: Point2(PosT), size: Point2(SizeT)) Self {
            return Self{
                .x = pos.x,
                .y = pos.y,
                .w = size.x,
                .h = size.y,
            };
        }

        pub fn intoPoints(self: Self) struct { pos: Point2(PosT), size: Point2(SizeT) } {
            return .{
                .pos = .{ .x = self.x, .y = self.y },
                .size = .{ .x = self.w, .y = self.h },
            };
        }
    };
}

pub fn Point2(comptime T: type) type {
    return struct {
        x: T,
        y: T,
    };
}
