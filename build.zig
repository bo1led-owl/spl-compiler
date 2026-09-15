const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const target = if (optimize != .ReleaseFast)
        // workaround for Zig's linker failure with glibc
        b.standardTargetOptions(.{ .default_target = .{ .abi = .musl } })
    else
        b.standardTargetOptions(.{});

    const mod = b.addModule("spl", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .link_libc = true,
    });

    linkLlvm(b, mod);

    const exe = b.addExecutable(.{
        .name = "splc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "spl", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}

fn linkLlvm(b: *std.Build, mod: *std.Build.Module) void {
    const llvm_include_dir =
        b.option([]const u8, "llvmIncludeDir", "LLVM include dir") orelse
        "/usr/include";
    const llvm_lib_dir =
        b.option([]const u8, "llvmLibDir", "LLVM library dir") orelse
        "/usr/lib";

    var llvm_lib_name = b.option([]const u8, "llvmLibName", "LLVM library name") orelse "LLVM-22";
    if (std.mem.startsWith(u8, llvm_lib_name, "-l")) {
        llvm_lib_name = llvm_lib_name[2..];
    }

    mod.addIncludePath(.{ .cwd_relative = llvm_include_dir });
    mod.addLibraryPath(.{ .cwd_relative = llvm_lib_dir });
    mod.linkSystemLibrary(llvm_lib_name, .{});
}
