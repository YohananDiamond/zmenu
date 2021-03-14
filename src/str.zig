pub const StringConfig = struct {
    mode: Mode = .Optimized,

    const Mode = enum {
        Accurate,
        Optimized,
    };
};

pub fn equals(lhs: [:0]const u8, rhs: [:0]const u8, config: StringConfig) bool {
    switch (config.mode) {
        .Accurate => {},
        .Optimized => if (lhs.len != rhs.len) return false,
    }

    for (lhs) |lhs_c, i| {
        const rhs_c = rhs[i]; // this should not be unsafe since in the worst case it stops at the null character.

        if (lhs_c != rhs_c) return false;
    } else {
        return true;
    }
}

test "equals" {
    const expect = @import("std").testing.expect;

    expect(equals("foo", "foo", .{}));
    expect(equals("ç", "ç", .{}));
    expect(!equals("foo", "bar", .{}));
}

pub fn equalsAny(lhs: [:0]const u8, comparations: anytype, config: StringConfig) bool {
    inline for (comparations) |rhs| {
        if (equals(lhs, rhs, config)) return true;
    } else {
        return false;
    }
}

test "equalsAny" {
    const expect = @import("std").testing.expect;

    expect(!equalsAny("foo", .{"fod", "bar", "abc"}, .{}));
    expect(equalsAny("foo", .{"fod", "foo", "abc"}, .{}));
}
