const std = @import("std");
const vk = @import("vulkan");
const c = @import("c");
const Window = @import("window.zig").Window;
const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Swapchain = @import("swapchain.zig").Swapchain;
const math = @import("util/math.zig");
const Mat4 = math.mat4.Mat4;
const Allocator = std.mem.Allocator;

const vert_spv align(@alignOf(u32)) = @embedFile("vertex_shader").*;
const frag_spv align(@alignOf(u32)) = @embedFile("fragment_shader").*;

const app_name = "vulkan-zig triangle example";

const Vertex = struct {
    const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "color"),
        },
    };

    pos: [3]f32,
    color: [3]f32,
};

const vertices = [_]Vertex{
    // Front face (+Z, red)
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ 0.5, -0.5, 0.5 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .color = .{ 1, 0, 0 } },

    // Back face (-Z, green)
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ -0.5, 0.5, -0.5 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .color = .{ 0, 1, 0 } },

    // Right face (+X, blue)
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .color = .{ 0, 0, 1 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .color = .{ 0, 0, 1 } },
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .color = .{ 0, 0, 1 } },
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .color = .{ 0, 0, 1 } },
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .color = .{ 0, 0, 1 } },
    .{ .pos = .{ 0.5, -0.5, 0.5 }, .color = .{ 0, 0, 1 } },

    // Left face (-X, yellow)
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .color = .{ 1, 1, 0 } },
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .color = .{ 1, 1, 0 } },
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .color = .{ 1, 1, 0 } },
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .color = .{ 1, 1, 0 } },
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .color = .{ 1, 1, 0 } },
    .{ .pos = .{ -0.5, 0.5, -0.5 }, .color = .{ 1, 1, 0 } },

    // Top face (+Y, magenta)
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .color = .{ 1, 0, 1 } },
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .color = .{ 1, 0, 1 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .color = .{ 1, 0, 1 } },
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .color = .{ 1, 0, 1 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .color = .{ 1, 0, 1 } },
    .{ .pos = .{ -0.5, 0.5, -0.5 }, .color = .{ 1, 0, 1 } },

    // Bottom face (-Y, cyan)
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .color = .{ 0, 1, 1 } },
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .color = .{ 0, 1, 1 } },
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .color = .{ 0, 1, 1 } },
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .color = .{ 0, 1, 1 } },
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .color = .{ 0, 1, 1 } },
    .{ .pos = .{ 0.5, -0.5, 0.5 }, .color = .{ 0, 1, 1 } },
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

    var framebuffers = try createFramebuffers(&gc, allocator, render_pass, swapchain);
    defer destroyFramebuffers(&gc, allocator, framebuffers);

    const pool = try gc.dev.createCommandPool(&.{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = gc.graphics_queue.family,
    }, null);
    defer gc.dev.destroyCommandPool(pool, null);

    const vertex_buffer = try gc.dev.createBuffer(&.{
        .size = @sizeOf(@TypeOf(vertices)),
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer gc.dev.destroyBuffer(vertex_buffer, null);
    const mem_reqs = gc.dev.getBufferMemoryRequirements(vertex_buffer);
    const memory = try gc.allocate(mem_reqs, .{ .device_local_bit = true });
    defer gc.dev.freeMemory(memory, null);
    try gc.dev.bindBufferMemory(vertex_buffer, memory, 0);

    try uploadVertices(&gc, pool, vertex_buffer);

    const UserPos = struct {
        x: f32 = 0,
        y: f32 = 0,
        z: f32 = 0,
        pitch: f32 = 0,
        yaw: f32 = 0,
        roll: f32 = 0,
    };

    var userPos = UserPos{};

    const computeMvp = struct {
        fn f(ext: vk.Extent2D, pos: UserPos) Mat4 {
            const aspect = @as(f32, @floatFromInt(ext.width)) /
                @as(f32, @floatFromInt(ext.height));
            const proj = math.mat4.perspective(std.math.degreesToRadians(60.0), aspect, 0.1, 100.0);
            const view = math.mat4.translate(0, 0, -2);
            const model = math.mat4.mul(math.mat4.mul(
                math.mat4.rotateX(pos.pitch),
                math.mat4.rotateY(pos.yaw),
            ), math.mat4.rotateZ(pos.roll));
            return math.mat4.mul(proj, math.mat4.mul(view, model));
        }
    }.f;

    var cmdbufs = try allocateCommandBuffers(&gc, pool, allocator, framebuffers.len);
    defer destroyCommandBuffers(&gc, pool, allocator, cmdbufs);

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
            userPos.pitch -= 0.001;
        if (c.glfwGetKey(window.window, c.GLFW_KEY_DOWN) == c.GLFW_PRESS)
            userPos.pitch += 0.001;

        if (state == .suboptimal or extent.width != @as(u32, @intCast(w)) or extent.height != @as(u32, @intCast(h))) {
            extent.width = @intCast(w);
            extent.height = @intCast(h);

            try swapchain.recreate(extent);

            destroyFramebuffers(&gc, allocator, framebuffers);
            framebuffers = try createFramebuffers(&gc, allocator, render_pass, swapchain);

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
            mvp,
        );

        state = swapchain.present(cmdbuf) catch |err| switch (err) {
            error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
            else => |narrow| return narrow,
        };

        c.glfwPollEvents();
    }

    try swapchain.waitForAllFences();
    try gc.dev.deviceWaitIdle();
}

fn uploadVertices(gc: *const GraphicsContext, pool: vk.CommandPool, buffer: vk.Buffer) !void {
    const staging_buffer = try gc.dev.createBuffer(&.{
        .size = @sizeOf(@TypeOf(vertices)),
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

        const gpu_vertices: [*]Vertex = @ptrCast(@alignCast(data));
        @memcpy(gpu_vertices, vertices[0..]);
    }

    try copyBuffer(gc, pool, buffer, staging_buffer, @sizeOf(@TypeOf(vertices)));
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
    mvp: Mat4,
) !void {
    const clear = vk.ClearValue{
        .color = .{ .float_32 = .{ 0, 0, 0, 1 } },
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
        .clear_value_count = 1,
        .p_clear_values = @ptrCast(&clear),
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
    gc.dev.cmdDraw(cmdbuf, vertices.len, 1, 0, 0);

    gc.dev.cmdEndRenderPass(cmdbuf);
    try gc.dev.endCommandBuffer(cmdbuf);
}

fn destroyCommandBuffers(gc: *const GraphicsContext, pool: vk.CommandPool, allocator: Allocator, cmdbufs: []vk.CommandBuffer) void {
    gc.dev.freeCommandBuffers(pool, cmdbufs);
    allocator.free(cmdbufs);
}

fn createFramebuffers(gc: *const GraphicsContext, allocator: Allocator, render_pass: vk.RenderPass, swapchain: Swapchain) ![]vk.Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, swapchain.swap_images.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    errdefer for (framebuffers[0..i]) |fb| gc.dev.destroyFramebuffer(fb, null);

    for (framebuffers) |*fb| {
        fb.* = try gc.dev.createFramebuffer(&.{
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&swapchain.swap_images[i].view),
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
    const color_attachment = vk.AttachmentDescription{
        .format = swapchain.surface_format.format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .present_src_khr,
    };

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment_ref),
    };

    return try gc.dev.createRenderPass(&.{
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_attachment),
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
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
        .p_depth_stencil_state = null,
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
