const std = @import("std");

pub fn Point2(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        const Self = @This();

        pub fn new(x: T, y: T) callconv(.Inline) Self {
            return Self{ .x = x, .y = y };
        }

        pub fn asArray(self: *const Self) callconv(.Inline) [2]T {
            return [2]T{ self.x, self.y };
        }

        pub fn eql(self: *const Self, rhs: *const Self) bool {
            switch (@typeInfo(T)) {
                .Float, .Int => return self.x == rhs.x and self.y == rhs.y,
                else => |t| @compileError("No known way to safely compare instances of " ++ @typeName(T) ++ " (kind: " ++ t ++ ")"),
            }
        }
    };
}

test "Point2.eql" {
    const p1 = Point2(i32){ .x = 10, .y = 20 };
    const p2 = Point2(i32){ .x = 10, .y = 20 };

    std.testing.expect(p1.eql(&p2));
}

test "Point2.new" {
    const p1 = Point2(i32).new(10, 20);
    const p2 = Point2(i32){ .x = 10, .y = 20 };

    std.testing.expect(p1.eql(&p2));
}

test "Point2.asArray" {
    const a1 = Point2(i32).new(10, 20).asArray();
    const a2 = [2]i32{ 10, 20 };

    std.testing.expect(std.mem.eql(i32, &a1, &a2));
}
