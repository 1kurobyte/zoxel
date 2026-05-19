const std = @import("std");
const gpu = std.gpu;

const PushConstants = extern struct {
    mvp: [4]@Vector(4, f32),
};

const pc = @extern(*addrspace(.push_constant) PushConstants, .{
    .name = "pc",
});

const a_pos = @extern(*addrspace(.input) @Vector(3, f32), .{
    .name = "a_pos",
    .decoration = .{ .location = 0 },
});
const a_color = @extern(*addrspace(.input) @Vector(3, f32), .{
    .name = "a_color",
    .decoration = .{ .location = 1 },
});
const v_color = @extern(*addrspace(.output) @Vector(3, f32), .{
    .name = "v_color",
    .decoration = .{ .location = 0 },
});

export fn main() callconv(.spirv_vertex) void {
    const pos = @Vector(4, f32){ a_pos.*[0], a_pos.*[1], a_pos.*[2], 1.0 };
    const mvp = pc.*.mvp;
    gpu.position_out.* = .{
        mvp[0][0] * pos[0] + mvp[1][0] * pos[1] + mvp[2][0] * pos[2] + mvp[3][0] * pos[3],
        mvp[0][1] * pos[0] + mvp[1][1] * pos[1] + mvp[2][1] * pos[2] + mvp[3][1] * pos[3],
        mvp[0][2] * pos[0] + mvp[1][2] * pos[1] + mvp[2][2] * pos[2] + mvp[3][2] * pos[3],
        mvp[0][3] * pos[0] + mvp[1][3] * pos[1] + mvp[2][3] * pos[2] + mvp[3][3] * pos[3],
    };
    v_color.* = a_color.*;
}
