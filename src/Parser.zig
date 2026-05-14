const std = @import("std");
const Reader = @import("Reader.zig");
const Allocator = std.mem.Allocator;

pub const Vert = @Vector(4, f32);
pub const VertTex = @Vector(3, f32);
pub const VertNormal = @Vector(3, f32);
pub const VertParam = @Vector(3, f32);

pub const FaceVertex = struct { v: u32, vt: ?u32 = null, vn: ?u32 = null };
pub const Face = struct {
    verts: []FaceVertex,
    material: ?u32 = null,
    smoothing_group: u32 = 0,
};
pub const Line = []u32;
pub const Point = []u32;

pub const Mesh = struct {
    v: []Vert,
    vt: []VertTex,
    vn: []VertNormal,
    vp: []VertParam,
    f: []Face,
    l: []Line,
    p: []Point,
    materials: [][]const u8,
    mtllibs: [][]const u8,

    pub fn deinit(self: *Mesh, gpa: Allocator) void {
        for (self.f) |face| gpa.free(face.verts);
        for (self.l) |line| gpa.free(line);
        for (self.p) |point| gpa.free(point);
        for (self.materials) |name| gpa.free(name);
        for (self.mtllibs) |name| gpa.free(name);
        gpa.free(self.f);
        gpa.free(self.l);
        gpa.free(self.p);
        gpa.free(self.materials);
        gpa.free(self.mtllibs);
        gpa.free(self.v);
        gpa.free(self.vt);
        gpa.free(self.vn);
        gpa.free(self.vp);
        self.* = undefined;
    }
};

pub const Error = error{
    BadNumber,
    BadIndex,
    Truncated,
    DegenerateFace,
    DegenerateLine,
    DegeneratePoint,
} || Allocator.Error;

const Counts = struct { v: u32, vt: u32, vn: u32 };

pub fn parse(gpa: Allocator, data: []const u8) Error!Mesh {
    var v: std.ArrayList(Vert) = .empty;
    var vt: std.ArrayList(VertTex) = .empty;
    var vn: std.ArrayList(VertNormal) = .empty;
    var vp: std.ArrayList(VertParam) = .empty;
    var f: std.ArrayList(Face) = .empty;
    var l: std.ArrayList(Line) = .empty;
    var p: std.ArrayList(Point) = .empty;
    var materials: std.ArrayList([]const u8) = .empty;
    var mtllibs: std.ArrayList([]const u8) = .empty;

    errdefer {
        v.deinit(gpa);
        vt.deinit(gpa);
        vn.deinit(gpa);
        vp.deinit(gpa);
        for (f.items) |face| gpa.free(face.verts);
        f.deinit(gpa);
        for (l.items) |line| gpa.free(line);
        l.deinit(gpa);
        for (p.items) |point| gpa.free(point);
        p.deinit(gpa);
        for (materials.items) |name| gpa.free(name);
        materials.deinit(gpa);
        for (mtllibs.items) |name| gpa.free(name);
        mtllibs.deinit(gpa);
    }

    var current_material: ?u32 = null;
    var current_smoothing: u32 = 0;

    var it = Reader.LineIterator{ .rest = data };
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        if (line.len == 0 or line[0] == '#') continue;

        var toks = std.mem.tokenizeAny(u8, line, " \t");
        const directive = toks.next() orelse continue;

        if (std.mem.eql(u8, directive, "v")) {
            try v.append(gpa, try parseVert(&toks));
        } else if (std.mem.eql(u8, directive, "vn")) {
            try vn.append(gpa, try parseVec3(&toks));
        } else if (std.mem.eql(u8, directive, "vt")) {
            try vt.append(gpa, try parseVec3Padded(&toks));
        } else if (std.mem.eql(u8, directive, "vp")) {
            try vp.append(gpa, try parseVec3Padded(&toks));
        } else if (std.mem.eql(u8, directive, "f")) {
            const counts: Counts = .{
                .v = @intCast(v.items.len),
                .vt = @intCast(vt.items.len),
                .vn = @intCast(vn.items.len),
            };
            const verts = try parseFaceVerts(gpa, &toks, counts);
            try f.append(gpa, .{
                .verts = verts,
                .material = current_material,
                .smoothing_group = current_smoothing,
            });
        } else if (std.mem.eql(u8, directive, "l")) {
            try l.append(gpa, try parseIdxList(gpa, &toks, @intCast(v.items.len), 2, error.DegenerateLine));
        } else if (std.mem.eql(u8, directive, "p")) {
            try p.append(gpa, try parseIdxList(gpa, &toks, @intCast(v.items.len), 1, error.DegeneratePoint));
        } else if (std.mem.eql(u8, directive, "usemtl")) {
            const name = toks.next() orelse continue;
            current_material = try internMaterial(gpa, &materials, name);
        } else if (std.mem.eql(u8, directive, "mtllib")) {
            while (toks.next()) |name| {
                try mtllibs.append(gpa, try gpa.dupe(u8, name));
            }
        } else if (std.mem.eql(u8, directive, "s")) {
            const arg = toks.next() orelse continue;
            current_smoothing = if (std.mem.eql(u8, arg, "off"))
                0
            else
                std.fmt.parseInt(u32, arg, 10) catch return error.BadNumber;
        }
        // g / o: ignored for now
    }

    return .{
        .v = try v.toOwnedSlice(gpa),
        .vt = try vt.toOwnedSlice(gpa),
        .vn = try vn.toOwnedSlice(gpa),
        .vp = try vp.toOwnedSlice(gpa),
        .f = try f.toOwnedSlice(gpa),
        .l = try l.toOwnedSlice(gpa),
        .p = try p.toOwnedSlice(gpa),
        .materials = try materials.toOwnedSlice(gpa),
        .mtllibs = try mtllibs.toOwnedSlice(gpa),
    };
}

fn parseVert(toks: anytype) Error!Vert {
    const x = try parseF32(toks.next() orelse return error.Truncated);
    const y = try parseF32(toks.next() orelse return error.Truncated);
    const z = try parseF32(toks.next() orelse return error.Truncated);
    const w: f32 = if (toks.next()) |t| try parseF32(t) else 1.0;
    return .{ x, y, z, w };
}

fn parseVec3(toks: anytype) Error!@Vector(3, f32) {
    const x = try parseF32(toks.next() orelse return error.Truncated);
    const y = try parseF32(toks.next() orelse return error.Truncated);
    const z = try parseF32(toks.next() orelse return error.Truncated);
    return .{ x, y, z };
}

fn parseVec3Padded(toks: anytype) Error!@Vector(3, f32) {
    const x = try parseF32(toks.next() orelse return error.Truncated);
    const y: f32 = if (toks.next()) |t| try parseF32(t) else 0.0;
    const z: f32 = if (toks.next()) |t| try parseF32(t) else 0.0;
    return .{ x, y, z };
}

fn parseFaceVerts(gpa: Allocator, toks: anytype, counts: Counts) Error![]FaceVertex {
    var verts: std.ArrayList(FaceVertex) = .empty;
    errdefer verts.deinit(gpa);
    while (toks.next()) |tok| {
        try verts.append(gpa, try parseFaceVertex(tok, counts));
    }
    if (verts.items.len < 3) return error.DegenerateFace;
    return try verts.toOwnedSlice(gpa);
}

fn parseFaceVertex(token: []const u8, counts: Counts) Error!FaceVertex {
    var parts = std.mem.splitScalar(u8, token, '/');
    const v_tok = parts.next() orelse return error.BadIndex;
    if (v_tok.len == 0) return error.BadIndex;
    var fv: FaceVertex = .{ .v = try resolveIdx(v_tok, counts.v) };
    if (parts.next()) |t| if (t.len > 0) {
        fv.vt = try resolveIdx(t, counts.vt);
    };
    if (parts.next()) |t| if (t.len > 0) {
        fv.vn = try resolveIdx(t, counts.vn);
    };
    return fv;
}

fn parseIdxList(
    gpa: Allocator,
    toks: anytype,
    v_count: u32,
    min_len: usize,
    too_short: Error,
) Error![]u32 {
    var idx: std.ArrayList(u32) = .empty;
    errdefer idx.deinit(gpa);
    while (toks.next()) |tok| {
        var parts = std.mem.splitScalar(u8, tok, '/');
        const v_tok = parts.next() orelse return error.BadIndex;
        if (v_tok.len == 0) return error.BadIndex;
        try idx.append(gpa, try resolveIdx(v_tok, v_count));
    }
    if (idx.items.len < min_len) return too_short;
    return try idx.toOwnedSlice(gpa);
}

fn internMaterial(gpa: Allocator, materials: *std.ArrayList([]const u8), name: []const u8) Error!u32 {
    for (materials.items, 0..) |existing, i| {
        if (std.mem.eql(u8, existing, name)) return @intCast(i);
    }
    const owned = try gpa.dupe(u8, name);
    errdefer gpa.free(owned);
    try materials.append(gpa, owned);
    return @intCast(materials.items.len - 1);
}

fn parseF32(tok: []const u8) Error!f32 {
    return std.fmt.parseFloat(f32, tok) catch return error.BadNumber;
}

fn resolveIdx(tok: []const u8, count: u32) Error!u32 {
    const parsed = std.fmt.parseInt(i64, tok, 10) catch return error.BadIndex;
    if (parsed > 0) {
        const one_based: u64 = @intCast(parsed);
        if (one_based > count) return error.BadIndex;
        return @intCast(one_based - 1);
    } else if (parsed < 0) {
        const offset: u64 = @intCast(-parsed);
        if (offset > count) return error.BadIndex;
        return @intCast(@as(u64, count) - offset);
    } else {
        return error.BadIndex;
    }
}
