const std = @import("std");
const vk = @import("vulkan");
const c = @import("c");
const Window = @import("window.zig").Window;
const test_ = @import("window.zig");
const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Swapchain = @import("swapchain.zig").Swapchain;
const Mesh = @import("mesh.zig");
const Vertex = Mesh.Vertex;
const math = @import("util/math.zig");
const Mat4 = math.mat4.Mat4;
const Allocator = std.mem.Allocator;

const vert_spv align(@alignOf(u32)) = @embedFile("vertex_shader").*;
const frag_spv align(@alignOf(u32)) = @embedFile("fragment_shader").*;

const mesh_path = "assets/teapot.obj";

const depth_format: vk.Format = .d32_sfloat;

const Depth = struct {
    image: vk.Image,
    memory: vk.DeviceMemory,
    view: vk.ImageView,

    fn init(gc: *const GraphicsContext, extent: vk.Extent2D) !Depth {
        const image = try gc.dev.createImage(&.{
            .image_type = .@"2d",
            .format = depth_format,
            .extent = .{ .width = extent.width, .height = extent.height, .depth = 1 },
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .tiling = .optimal,
            .usage = .{ .depth_stencil_attachment_bit = true },
            .sharing_mode = .exclusive,
            .initial_layout = .undefined,
        }, null);
        errdefer gc.dev.destroyImage(image, null);

        const mem_reqs = gc.dev.getImageMemoryRequirements(image);
        const memory = try gc.allocate(mem_reqs, .{ .device_local_bit = true });
        errdefer gc.dev.freeMemory(memory, null);
        try gc.dev.bindImageMemory(image, memory, 0);

        const view = try gc.dev.createImageView(&.{
            .image = image,
            .view_type = .@"2d",
            .format = depth_format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .depth_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
        errdefer gc.dev.destroyImageView(view, null);

        return .{ .image = image, .memory = memory, .view = view };
    }

    fn deinit(self: Depth, gc: *const GraphicsContext) void {
        gc.dev.destroyImageView(self.view, null);
        gc.dev.destroyImage(self.image, null);
        gc.dev.freeMemory(self.memory, null);
    }
};

pub fn main(init: std.process.Init) !void {
    var window = try Window.init("Zoxel", 800, 600);
    defer window.deinit();

    var extent = vk.Extent2D{
        .width = window.width,
        .height = window.height,
    };

    const allocator = init.gpa;

    const gc = try GraphicsContext.init(allocator, window.title, window.window);
    defer gc.deinit();

    std.log.debug("Using device: {s}", .{gc.deviceName()});

    var swapchain = try Swapchain.init(&gc, allocator, extent);
    defer swapchain.deinit();

    var depth = try Depth.init(&gc, extent);
    defer depth.deinit(&gc);

    var triangulated = try Mesh.loadObj(init.io, allocator, mesh_path);
    defer triangulated.deinit(allocator);
    std.log.info("Loaded {s}: {d} verts, {d} indices", .{
        mesh_path,
        triangulated.vertices.len,
        triangulated.indices.len,
    });

    const push_constant_range = vk.PushConstantRange{
        .stage_flags = .{ .vertex_bit = true },
        .offset = 0,
        .size = @sizeOf(Mat4),
    };
    const pipeline_layout = try gc.dev.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 1,
        .p_push_constant_ranges = @ptrCast(&push_constant_range),
    }, null);
    defer gc.dev.destroyPipelineLayout(pipeline_layout, null);

    const render_pass = try createRenderPass(&gc, swapchain);
    defer gc.dev.destroyRenderPass(render_pass, null);

    const pipeline = try createPipeline(&gc, pipeline_layout, render_pass);
    defer gc.dev.destroyPipeline(pipeline, null);

    var framebuffers = try createFramebuffers(&gc, allocator, render_pass, swapchain, depth.view);
    defer destroyFramebuffers(&gc, allocator, framebuffers);

    const pool = try gc.dev.createCommandPool(&.{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = gc.graphics_queue.family,
    }, null);
    defer gc.dev.destroyCommandPool(pool, null);

    const vertex_bytes: vk.DeviceSize = triangulated.vertices.len * @sizeOf(Vertex);
    const vertex_buffer = try gc.dev.createBuffer(&.{
        .size = vertex_bytes,
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer gc.dev.destroyBuffer(vertex_buffer, null);
    const v_mem_reqs = gc.dev.getBufferMemoryRequirements(vertex_buffer);
    const vertex_memory = try gc.allocate(v_mem_reqs, .{ .device_local_bit = true });
    defer gc.dev.freeMemory(vertex_memory, null);
    try gc.dev.bindBufferMemory(vertex_buffer, vertex_memory, 0);

    const index_bytes: vk.DeviceSize = triangulated.indices.len * @sizeOf(u32);
    const index_buffer = try gc.dev.createBuffer(&.{
        .size = index_bytes,
        .usage = .{ .transfer_dst_bit = true, .index_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer gc.dev.destroyBuffer(index_buffer, null);
    const i_mem_reqs = gc.dev.getBufferMemoryRequirements(index_buffer);
    const index_memory = try gc.allocate(i_mem_reqs, .{ .device_local_bit = true });
    defer gc.dev.freeMemory(index_memory, null);
    try gc.dev.bindBufferMemory(index_buffer, index_memory, 0);

    try uploadToBuffer(&gc, pool, vertex_buffer, std.mem.sliceAsBytes(triangulated.vertices));
    try uploadToBuffer(&gc, pool, index_buffer, std.mem.sliceAsBytes(triangulated.indices));

    const index_count: u32 = @intCast(triangulated.indices.len);

    const UserPos = struct {
        x: f32 = 0,
        y: f32 = 0,
        z: f32 = 0,
        pitch: f32 = 0,
        yaw: f32 = 0,
        roll: f32 = 0,
    };

    var userPos = UserPos{};

    const camRotation = struct {
        fn f(pos: UserPos) Mat4 {
            // R_cam = rotateY(yaw) * rotateX(pitch) * rotateZ(roll)
            // yaw is applied last around world Y so pitch happens in the camera's
            // already-yawed local frame (standard FPS convention).
            return math.mat4.mul(math.mat4.mul(
                math.mat4.rotateY(pos.yaw),
                math.mat4.rotateX(pos.pitch),
            ), math.mat4.rotateZ(pos.roll));
        }
    }.f;

    const computeMvp = struct {
        fn f(ext: vk.Extent2D, pos: UserPos) Mat4 {
            const aspect = @as(f32, @floatFromInt(ext.width)) /
                @as(f32, @floatFromInt(ext.height));
            const proj = math.mat4.perspective(std.math.degreesToRadians(60.0), aspect, 0.1, 100.0);
            // View = R_cam^-1 * T(-cam_pos). Inverse of a rotation product is
            // reverse-order with negated angles.
            const view_rot = math.mat4.mul(math.mat4.mul(
                math.mat4.rotateZ(-pos.roll),
                math.mat4.rotateX(-pos.pitch),
            ), math.mat4.rotateY(-pos.yaw));
            const view_trans = math.mat4.translate(-pos.x, -pos.y, -pos.z - 2);
            const view = math.mat4.mul(view_rot, view_trans);
            return math.mat4.mul(proj, view);
        }
    }.f;

    var cmdbufs = try allocateCommandBuffers(&gc, pool, allocator, framebuffers.len);
    defer destroyCommandBuffers(&gc, pool, allocator, cmdbufs);

    var fps_window_start = std.Io.Clock.Timestamp.now(init.io, .awake);
    var frame_count: u32 = 0;

    var state: Swapchain.PresentState = .optimal;
    while (c.glfwWindowShouldClose(window.window) == c.GLFW_FALSE) {
        var w: c_int = undefined;
        var h: c_int = undefined;
        c.glfwGetFramebufferSize(window.window, &w, &h);

        // Don't present or resize swapchain while the window is minimized
        if (w == 0 or h == 0) {
            c.glfwPollEvents();
            continue;
        }

        if (c.glfwGetKey(window.window, c.GLFW_KEY_LEFT) == c.GLFW_PRESS)
            userPos.yaw += 0.001;
        if (c.glfwGetKey(window.window, c.GLFW_KEY_RIGHT) == c.GLFW_PRESS)
            userPos.yaw -= 0.001;
        if (c.glfwGetKey(window.window, c.GLFW_KEY_UP) == c.GLFW_PRESS)
            userPos.pitch += 0.001;
        if (c.glfwGetKey(window.window, c.GLFW_KEY_DOWN) == c.GLFW_PRESS)
            userPos.pitch -= 0.001;
        if (c.glfwGetKey(window.window, c.GLFW_KEY_Q) == c.GLFW_PRESS)
            userPos.roll += 0.001;
        if (c.glfwGetKey(window.window, c.GLFW_KEY_E) == c.GLFW_PRESS)
            userPos.roll -= 0.001;

        var dx: f32 = 0;
        var dy: f32 = 0;
        var dz: f32 = 0;
        if (c.glfwGetKey(window.window, c.GLFW_KEY_W) == c.GLFW_PRESS)
            dz -= 0.001;
        if (c.glfwGetKey(window.window, c.GLFW_KEY_S) == c.GLFW_PRESS)
            dz += 0.001;
        if (c.glfwGetKey(window.window, c.GLFW_KEY_A) == c.GLFW_PRESS)
            dx -= 0.001;
        if (c.glfwGetKey(window.window, c.GLFW_KEY_D) == c.GLFW_PRESS)
            dx += 0.001;
        if (c.glfwGetKey(window.window, c.GLFW_KEY_SPACE) == c.GLFW_PRESS)
            dy += 0.001;
        if (c.glfwGetKey(window.window, c.GLFW_KEY_LEFT_SHIFT) == c.GLFW_PRESS or c.glfwGetKey(window.window, c.GLFW_KEY_RIGHT_SHIFT) == c.GLFW_PRESS)
            dy -= 0.001;

        const rot = camRotation(userPos);
        userPos.x += rot[0] * dx + rot[4] * dy + rot[8] * dz;
        userPos.y += rot[1] * dx + rot[5] * dy + rot[9] * dz;
        userPos.z += rot[2] * dx + rot[6] * dy + rot[10] * dz;

        if (state == .suboptimal or extent.width != @as(u32, @intCast(w)) or extent.height != @as(u32, @intCast(h))) {
            extent.width = @intCast(w);
            extent.height = @intCast(h);

            try swapchain.recreate(extent);

            depth.deinit(&gc);
            depth = try Depth.init(&gc, extent);

            destroyFramebuffers(&gc, allocator, framebuffers);
            framebuffers = try createFramebuffers(&gc, allocator, render_pass, swapchain, depth.view);

            destroyCommandBuffers(&gc, pool, allocator, cmdbufs);
            cmdbufs = try allocateCommandBuffers(&gc, pool, allocator, framebuffers.len);
        }

        const image_index = swapchain.image_index;
        const cmdbuf = cmdbufs[image_index];

        try swapchain.waitForCurrentFence();

        const mvp = computeMvp(swapchain.extent, userPos);
        try gc.dev.resetCommandBuffer(cmdbuf, .{});
        try recordCommandBuffer(
            &gc,
            cmdbuf,
            framebuffers[image_index],
            swapchain.extent,
            render_pass,
            pipeline,
            pipeline_layout,
            vertex_buffer,
            index_buffer,
            index_count,
            mvp,
        );

        state = swapchain.present(cmdbuf) catch |err| switch (err) {
            error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
            else => |narrow| return narrow,
        };

        frame_count += 1;
        const elapsed = fps_window_start.untilNow(init.io);
        if (elapsed.raw.nanoseconds >= std.time.ns_per_s) {
            std.log.info("FPS: {d}", .{frame_count});
            frame_count = 0;
            fps_window_start = std.Io.Clock.Timestamp.now(init.io, .awake);
        }

        c.glfwPollEvents();
    }

    try swapchain.waitForAllFences();
    try gc.dev.deviceWaitIdle();
}

fn uploadToBuffer(
    gc: *const GraphicsContext,
    pool: vk.CommandPool,
    dst: vk.Buffer,
    bytes: []const u8,
) !void {
    const staging_buffer = try gc.dev.createBuffer(&.{
        .size = bytes.len,
        .usage = .{ .transfer_src_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer gc.dev.destroyBuffer(staging_buffer, null);
    const mem_reqs = gc.dev.getBufferMemoryRequirements(staging_buffer);
    const staging_memory = try gc.allocate(mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
    defer gc.dev.freeMemory(staging_memory, null);
    try gc.dev.bindBufferMemory(staging_buffer, staging_memory, 0);

    {
        const data = try gc.dev.mapMemory(staging_memory, 0, vk.WHOLE_SIZE, .{});
        defer gc.dev.unmapMemory(staging_memory);

        const dst_bytes: [*]u8 = @ptrCast(data);
        @memcpy(dst_bytes[0..bytes.len], bytes);
    }

    try copyBuffer(gc, pool, dst, staging_buffer, bytes.len);
}

fn copyBuffer(
    gc: *const GraphicsContext,
    pool: vk.CommandPool,
    dst: vk.Buffer,
    src: vk.Buffer,
    size: vk.DeviceSize,
) !void {
    var cmdbuf_handle: vk.CommandBuffer = undefined;
    try gc.dev.allocateCommandBuffers(&.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf_handle));
    defer gc.dev.freeCommandBuffers(pool, &.{cmdbuf_handle});

    const cmdbuf = GraphicsContext.CommandBuffer.init(cmdbuf_handle, gc.dev.wrapper);

    try cmdbuf.beginCommandBuffer(&.{
        .flags = .{ .one_time_submit_bit = true },
    });

    const region = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    };
    cmdbuf.copyBuffer(src, dst, &.{region});

    try cmdbuf.endCommandBuffer();

    const si = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = &.{cmdbuf.handle},
        .p_wait_dst_stage_mask = undefined,
    };
    try gc.dev.queueSubmit(gc.graphics_queue.handle, &.{si}, .null_handle);
    try gc.dev.queueWaitIdle(gc.graphics_queue.handle);
}

fn allocateCommandBuffers(
    gc: *const GraphicsContext,
    pool: vk.CommandPool,
    allocator: Allocator,
    count: usize,
) ![]vk.CommandBuffer {
    const cmdbufs = try allocator.alloc(vk.CommandBuffer, count);
    errdefer allocator.free(cmdbufs);

    try gc.dev.allocateCommandBuffers(&.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = @intCast(cmdbufs.len),
    }, cmdbufs.ptr);

    return cmdbufs;
}

fn recordCommandBuffer(
    gc: *const GraphicsContext,
    cmdbuf: vk.CommandBuffer,
    framebuffer: vk.Framebuffer,
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    pipeline: vk.Pipeline,
    pipeline_layout: vk.PipelineLayout,
    vertex_buffer: vk.Buffer,
    index_buffer: vk.Buffer,
    index_count: u32,
    mvp: Mat4,
) !void {
    const clears = [_]vk.ClearValue{
        .{ .color = .{ .float_32 = .{ 0, 0, 0, 1 } } },
        .{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
    };

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(extent.width),
        .height = @floatFromInt(extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };

    try gc.dev.beginCommandBuffer(cmdbuf, &.{});

    gc.dev.cmdSetViewport(cmdbuf, 0, &.{viewport});
    gc.dev.cmdSetScissor(cmdbuf, 0, &.{scissor});

    // This needs to be a separate definition - see https://github.com/ziglang/zig/issues/7627.
    const render_area = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };

    gc.dev.cmdBeginRenderPass(cmdbuf, &.{
        .render_pass = render_pass,
        .framebuffer = framebuffer,
        .render_area = render_area,
        .clear_value_count = clears.len,
        .p_clear_values = &clears,
    }, .@"inline");

    gc.dev.cmdBindPipeline(cmdbuf, .graphics, pipeline);
    gc.dev.cmdPushConstants(
        cmdbuf,
        pipeline_layout,
        .{ .vertex_bit = true },
        0,
        @sizeOf(Mat4),
        @ptrCast(&mvp),
    );
    const offset = [_]vk.DeviceSize{0};
    gc.dev.cmdBindVertexBuffers(cmdbuf, 0, &.{vertex_buffer}, &offset);
    gc.dev.cmdBindIndexBuffer(cmdbuf, index_buffer, 0, .uint32);
    gc.dev.cmdDrawIndexed(cmdbuf, index_count, 1, 0, 0, 0);

    gc.dev.cmdEndRenderPass(cmdbuf);
    try gc.dev.endCommandBuffer(cmdbuf);
}

fn destroyCommandBuffers(gc: *const GraphicsContext, pool: vk.CommandPool, allocator: Allocator, cmdbufs: []vk.CommandBuffer) void {
    gc.dev.freeCommandBuffers(pool, cmdbufs);
    allocator.free(cmdbufs);
}

fn createFramebuffers(
    gc: *const GraphicsContext,
    allocator: Allocator,
    render_pass: vk.RenderPass,
    swapchain: Swapchain,
    depth_view: vk.ImageView,
) ![]vk.Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, swapchain.swap_images.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    errdefer for (framebuffers[0..i]) |fb| gc.dev.destroyFramebuffer(fb, null);

    for (framebuffers) |*fb| {
        const attachments = [_]vk.ImageView{ swapchain.swap_images[i].view, depth_view };
        fb.* = try gc.dev.createFramebuffer(&.{
            .render_pass = render_pass,
            .attachment_count = attachments.len,
            .p_attachments = &attachments,
            .width = swapchain.extent.width,
            .height = swapchain.extent.height,
            .layers = 1,
        }, null);
        i += 1;
    }

    return framebuffers;
}

fn destroyFramebuffers(gc: *const GraphicsContext, allocator: Allocator, framebuffers: []const vk.Framebuffer) void {
    for (framebuffers) |fb| gc.dev.destroyFramebuffer(fb, null);
    allocator.free(framebuffers);
}

fn createRenderPass(gc: *const GraphicsContext, swapchain: Swapchain) !vk.RenderPass {
    const attachments = [_]vk.AttachmentDescription{
        .{
            .format = swapchain.surface_format.format,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .present_src_khr,
        },
        .{
            .format = depth_format,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .dont_care,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .depth_stencil_attachment_optimal,
        },
    };

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };
    const depth_attachment_ref = vk.AttachmentReference{
        .attachment = 1,
        .layout = .depth_stencil_attachment_optimal,
    };

    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment_ref),
        .p_depth_stencil_attachment = &depth_attachment_ref,
    };

    // Serialize color + depth writes between consecutive frames using the
    // same attachments.
    const dependency = vk.SubpassDependency{
        .src_subpass = vk.SUBPASS_EXTERNAL,
        .dst_subpass = 0,
        .src_stage_mask = .{
            .color_attachment_output_bit = true,
            .early_fragment_tests_bit = true,
            .late_fragment_tests_bit = true,
        },
        .dst_stage_mask = .{
            .color_attachment_output_bit = true,
            .early_fragment_tests_bit = true,
        },
        .src_access_mask = .{
            .color_attachment_write_bit = true,
            .depth_stencil_attachment_write_bit = true,
        },
        .dst_access_mask = .{
            .color_attachment_write_bit = true,
            .depth_stencil_attachment_read_bit = true,
            .depth_stencil_attachment_write_bit = true,
        },
    };

    return try gc.dev.createRenderPass(&.{
        .attachment_count = attachments.len,
        .p_attachments = &attachments,
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
        .dependency_count = 1,
        .p_dependencies = @ptrCast(&dependency),
    }, null);
}

fn createPipeline(
    gc: *const GraphicsContext,
    layout: vk.PipelineLayout,
    render_pass: vk.RenderPass,
) !vk.Pipeline {
    const vert = try gc.dev.createShaderModule(&.{
        .code_size = vert_spv.len,
        .p_code = @ptrCast(&vert_spv),
    }, null);
    defer gc.dev.destroyShaderModule(vert, null);

    const frag = try gc.dev.createShaderModule(&.{
        .code_size = frag_spv.len,
        .p_code = @ptrCast(&frag_spv),
    }, null);
    defer gc.dev.destroyShaderModule(frag, null);

    const pssci = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .stage = .{ .vertex_bit = true },
            .module = vert,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = frag,
            .p_name = "main",
        },
    };

    const pvisci = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast(&Vertex.binding_description),
        .vertex_attribute_description_count = Vertex.attribute_description.len,
        .p_vertex_attribute_descriptions = &Vertex.attribute_description,
    };

    const piasci = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_list,
        .primitive_restart_enable = .false,
    };

    const pvsci = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = undefined, // set in recordCommandBuffers with cmdSetViewport
        .scissor_count = 1,
        .p_scissors = undefined, // set in recordCommandBuffers with cmdSetScissor
    };

    const prsci = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = .false,
        .rasterizer_discard_enable = .false,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = true },
        .front_face = .counter_clockwise,
        .depth_bias_enable = .false,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const pmsci = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = .false,
        .min_sample_shading = 1,
        .alpha_to_coverage_enable = .false,
        .alpha_to_one_enable = .false,
    };

    const pcbas = vk.PipelineColorBlendAttachmentState{
        .blend_enable = .false,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const pcbsci = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = .false,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&pcbas),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const dynstate = [_]vk.DynamicState{ .viewport, .scissor };
    const pdsci = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynstate.len,
        .p_dynamic_states = &dynstate,
    };

    const noop_stencil: vk.StencilOpState = .{
        .fail_op = .keep,
        .pass_op = .keep,
        .depth_fail_op = .keep,
        .compare_op = .always,
        .compare_mask = 0,
        .write_mask = 0,
        .reference = 0,
    };
    const pdssci = vk.PipelineDepthStencilStateCreateInfo{
        .depth_test_enable = .true,
        .depth_write_enable = .true,
        .depth_compare_op = .less_or_equal,
        .depth_bounds_test_enable = .false,
        .stencil_test_enable = .false,
        .front = noop_stencil,
        .back = noop_stencil,
        .min_depth_bounds = 0,
        .max_depth_bounds = 1,
    };

    const gpci = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = 2,
        .p_stages = &pssci,
        .p_vertex_input_state = &pvisci,
        .p_input_assembly_state = &piasci,
        .p_tessellation_state = null,
        .p_viewport_state = &pvsci,
        .p_rasterization_state = &prsci,
        .p_multisample_state = &pmsci,
        .p_depth_stencil_state = &pdssci,
        .p_color_blend_state = &pcbsci,
        .p_dynamic_state = &pdsci,
        .layout = layout,
        .render_pass = render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try gc.dev.createGraphicsPipelines(
        .null_handle,
        &.{gpci},
        null,
        (&pipeline)[0..1],
    );
    return pipeline;
}
