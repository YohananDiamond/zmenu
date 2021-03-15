const Builder = @import("std").build.Builder;

/// Quick general build config struct.
const build_config = .{
    .use_xinerama = true,
};

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zmenu", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    // Executable configuration
    {
        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        // Set up build options
        exe.addBuildOption(bool, "use_xinerama", build_config.use_xinerama);

        const c_flags = &[_][]const u8 {"-std=c99"};

        exe.addIncludeDir("src/c_impl");
        exe.addCSourceFile("src/c_impl/zmenu_xlib.c", c_flags);

        exe.linkSystemLibrary("c");
        exe.linkSystemLibrary("X11");
        exe.linkSystemLibrary("Xft");
        exe.linkSystemLibrary("fontconfig");

        if (build_config.use_xinerama) {
            exe.linkSystemLibrary("Xinerama");
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    // Testing
    {
        const tests = b.addTest("src/main.zig");

        const test_step = b.step("test", "Test the app");
        test_step.dependOn(&tests.step);
    }
}
