const std = @import("std");
const vk = @import("vulkan");
const Parser = @import("Parser.zig");
const Reader = @import("Reader.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Vertex = struct {
    pos: [3]f32,
    color: [3]f32,

    pub const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    };

    pub const attribute_description = [_]vk.VertexInputAttributeDescription{
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
};

pub const Triangulated = struct {
    vertices: []Vertex,
    indices: []u32,

    pub fn deinit(self: *Triangulated, gpa: Allocator) void {
        gpa.free(self.vertices);
        gpa.free(self.indices);
        self.* = undefined;
    }
};

pub const LoadError = Reader.FileReader.OpenError || Parser.Error;

pub fn loadObj(io: Io, gpa: Allocator, path: []const u8) LoadError!Triangulated {
    var fr = try Reader.FileReader.open(io, .cwd(), path);
    defer fr.close(io);

    var mesh = try Parser.parse(gpa, fr.data);
    defer mesh.deinit(gpa);

    return triangulate(gpa, mesh);
}

fn triangulate(gpa: Allocator, mesh: Parser.Mesh) Allocator.Error!Triangulated {
    var min = [3]f32{ std.math.inf(f32), std.math.inf(f32), std.math.inf(f32) };
    var max = [3]f32{ -std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32) };
    for (mesh.v) |v4| {
        inline for (0..3) |i| {
            min[i] = @min(min[i], v4[i]);
            max[i] = @max(max[i], v4[i]);
        }
    }
    const center = [3]f32{
        (min[0] + max[0]) * 0.5,
        (min[1] + max[1]) * 0.5,
        (min[2] + max[2]) * 0.5,
    };
    const span = @max(@max(max[0] - min[0], max[1] - min[1]), max[2] - min[2]);
    const scale: f32 = if (span > 0) 1.0 / span else 1.0;

    const vertices = try gpa.alloc(Vertex, mesh.v.len);
    errdefer gpa.free(vertices);
    for (mesh.v, vertices) |src, *dst| {
        const px = (src[0] - center[0]) * scale;
        const py = (src[1] - center[1]) * scale;
        const pz = (src[2] - center[2]) * scale;
        dst.* = .{
            .pos = .{ px, py, pz },
            .color = .{ px + 0.5, py + 0.5, pz + 0.5 },
        };
    }

    var tri_count: usize = 0;
    for (mesh.f) |face| {
        if (face.verts.len >= 3) tri_count += face.verts.len - 2;
    }

    const indices = try gpa.alloc(u32, tri_count * 3);
    errdefer gpa.free(indices);
    var w: usize = 0;
    for (mesh.f) |face| {
        if (face.verts.len < 3) continue;
        const v0 = face.verts[0].v;
        for (1..face.verts.len - 1) |i| {
            indices[w] = v0;
            indices[w + 1] = face.verts[i].v;
            indices[w + 2] = face.verts[i + 1].v;
            w += 3;
        }
    }

    return .{ .vertices = vertices, .indices = indices };
}
