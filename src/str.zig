const ComparationMode = enum {
    Accurate,
    Optimized,
};

pub fn eql(lhs: [:0]const u8, rhs: [:0]const u8, mode: ComparationMode) bool {
    switch (mode) {
        .Accurate => {},
        .Optimized => if (lhs.len != rhs.len) return false,
    }

    for (lhs) |lhs_c, i| {
        if (lhs_c != rhs[i]) return false;
    }

    return true;
}

test "equals" {
    const expect = @import("std").testing.expect;

    expect(eql("foo", "foo", .Optimized));
    expect(eql("ç", "ç", .Optimized));
    expect(!eql("foo", "bar", .Optimized));
}

pub fn eqlAny(lhs: [:0]const u8, comparations: anytype, mode: ComparationMode) callconv(.Inline) bool {
    inline for (comparations) |rhs| {
        if (eql(lhs, rhs, mode)) return true;
    } else {
        return false;
    }
}

test "equalsAny" {
    const expect = @import("std").testing.expect;

    expect(!eqlAny("foo", .{ "fod", "bar", "abc" }, .Optimized));
    expect(eqlAny("foo", .{ "fod", "foo", "abc" }, .Optimized));
}
