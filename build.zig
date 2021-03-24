const std = @import("std");

const config = .{
    .use_xinerama = true,
};

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    // Executable configuration
    {
        const exe = b.addExecutable("zmenu", "src/main.zig");
        exe.install();

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        configureStep(exe, target, mode);

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    // Testing configuration
    {
        const tests = b.addTest("src/main.zig");

        configureStep(tests, target, mode);

        const test_step = b.step("test", "Test the app");
        test_step.dependOn(&tests.step);
    }
}

fn configureStep(
    step: *std.build.LibExeObjStep,
    target: anytype, // FIXME: how do I describe this type
    mode: std.builtin.Mode,
) void {
    step.addBuildOption(bool, "use_xinerama", config.use_xinerama);

    if (config.use_xinerama) {
        step.linkSystemLibrary("Xinerama");
    }

    step.setTarget(target);
    step.setBuildMode(mode);

    step.linkSystemLibrary("c");
    step.linkSystemLibrary("X11");
    step.linkSystemLibrary("Xft");
    step.linkSystemLibrary("fontconfig");

    const c_flags = &[_][]const u8{"-std=c99"};
    step.addIncludeDir("src/c_impl");
    step.addCSourceFile("src/c_impl/zmenu_xlib.c", c_flags);
}
