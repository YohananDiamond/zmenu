const BaseConfig = @import("api.zig").BaseConfig;
const Resources = @import("api.zig").Resources;
const SchemeStrings = @import("api.zig").SchemeStrings;

pub const cfg = BaseConfig{
    .position = .Centered,
    .fuzzy = false,
    .case_sensitive = false,

    .lines = 20,

    .default_resources = Resources{
        .normal = .{ .fg = "#FBF1C7", .bg = "#282828" },
        .normal_highlight = .{ .fg = "#FABD2F", .bg = "#282828" },
        .sel = .{ .fg = "#282828", .bg = "#FBF1C7" },
        .sel_highlight = .{ .fg = "#282828", .bg = "#FABD2F" },
        .out = .{ .fg = "#282828", .bg = "#9D0006" },

        .fonts = &[_][:0]const u8 {
            "monospace:size=11",
        },
    },

    .prompt = null,

    .word_delimeters = &[_]u8 {' '},
    .border_width = 0,

    .grab_kb = .Early,
};
