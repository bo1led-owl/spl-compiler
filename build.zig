const std = @import("std");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const translate_c = b.dependency("translate_c", .{});
    const translator: Translator = .init(translate_c, .{
        .c_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
        .link_system_libs = &.{
            .{ .name = "LLVM-23", .options = .{} },
        },
    });

    const llvm_config_output = b.run(&.{ "llvm-config", "--cflags" });
    var args = std.mem.splitAny(u8, llvm_config_output, &std.ascii.whitespace);
    while (args.next()) |arg| {
        if (arg.len == 0) {
            continue;
        }
        translator.run.addArg(arg);
    }

    const frontend = b.addModule("frontend", .{
        .root_source_file = b.path("src/frontend/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "c", .module = translator.mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "splc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/driver/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "frontend", .module = frontend },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const mod_tests = b.addTest(.{ .root_module = frontend });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
