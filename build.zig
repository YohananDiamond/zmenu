const std = @import("std");
const Pkg = std.build.Pkg;

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
        const test_roots = &[_][]const u8{
            "src/main.zig",
            "x11/x11.zig",
        };

        const test_step = b.step("test", "Test the app");

        for (test_roots) |test_root| {
            const test_ = b.addTest(test_root);
            configureStep(test_, target, mode);
            test_step.dependOn(&test_.step);
        }
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

    {
        // X11 Package
        step.addPackage(Pkg{
            .name = "x11",
            .path = "x11/x11.zig",
        });

        step.addIncludeDir("x11");
        step.addCSourceFile("x11/funcs.c", &.{"-std=c99"});

        step.linkSystemLibrary("c");
        step.linkSystemLibrary("X11");
    }

    // step.linkSystemLibrary("Xft");
    // step.linkSystemLibrary("fontconfig");

}
