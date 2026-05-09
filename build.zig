const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .abi = .gnu,
        },
    });
    const optimize = b.standardOptimizeOption(.{});
    const use_zig_shaders = b.option(bool, "zig-shader", "Use Zig shaders instead of GLSL") orelse false;

    const glfw = b.dependency("glfw", .{
        .target = target,
        .optimize = optimize,
        .wayland = true,
    });

    const glfw_lib = glfw.artifact("glfw");

    const trans_glfw = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .link_libc = true,
        .target = target,
        .optimize = optimize,
    });

    const vulkan = b.dependency("vulkan", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    }).module("vulkan-zig");

    trans_glfw.step.dependOn(&glfw_lib.step);

    trans_glfw.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
    trans_glfw.addSystemIncludePath(glfw_lib.getEmittedIncludeTree());

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "c", .module = trans_glfw.createModule() },
            .{ .name = "vulkan", .module = vulkan },
        },
    });

    if (use_zig_shaders) {
        const spirv_target = b.resolveTargetQuery(.{
            .cpu_arch = .spirv32,
            .os_tag = .vulkan,
            .cpu_model = .{ .explicit = &std.Target.spirv.cpu.vulkan_v1_2 },
            .ofmt = .spirv,
        });

        const vert_spv = b.addObject(.{
            .name = "vertex_shader",
            .root_module = b.createModule(.{
                .root_source_file = b.path("shaders/vertex.zig"),
                .target = spirv_target,
            }),
            .use_llvm = false,
        });
        exe_mod.addAnonymousImport(
            "vertex_shader",
            .{ .root_source_file = vert_spv.getEmittedBin() },
        );

        const frag_spv = b.addObject(.{
            .name = "fragment_shader",
            .root_module = b.createModule(.{
                .root_source_file = b.path("shaders/fragment.zig"),
                .target = spirv_target,
            }),
            .use_llvm = false,
        });
        exe_mod.addAnonymousImport(
            "fragment_shader",
            .{ .root_source_file = frag_spv.getEmittedBin() },
        );
    } else {
        const vert_cmd = b.addSystemCommand(&.{
            "glslc",
            "--target-env=vulkan1.2",
            "-o",
        });
        const vert_spv = vert_cmd.addOutputFileArg("vert.spv");
        vert_cmd.addFileArg(b.path("shaders/triangle.vert"));
        exe_mod.addAnonymousImport("vertex_shader", .{
            .root_source_file = vert_spv,
        });

        const frag_cmd = b.addSystemCommand(&.{
            "glslc",
            "--target-env=vulkan1.2",
            "-o",
        });
        const frag_spv = frag_cmd.addOutputFileArg("frag.spv");
        frag_cmd.addFileArg(b.path("shaders/triangle.frag"));
        exe_mod.addAnonymousImport("fragment_shader", .{
            .root_source_file = frag_spv,
        });
    }

    exe_mod.linkLibrary(glfw.artifact("glfw"));

    const exe = b.addExecutable(.{
        .name = "zoxel",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
