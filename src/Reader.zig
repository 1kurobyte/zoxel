const std = @import("std");
const Io = std.Io;
const File = std.Io.File;

pub const FileReader = struct {
    data: []const u8,
    file: File,
    mapping: ?File.MemoryMap,

    pub const OpenError = File.OpenError ||
        File.LengthError ||
        File.MemoryMap.CreateError ||
        error{FileTooBig};

    pub fn open(io: Io, dir: std.Io.Dir, sub_path: []const u8) OpenError!FileReader {
        const file = try dir.openFile(io, sub_path, .{});
        errdefer file.close(io);

        const size_u64 = try file.length(io);
        const size = std.math.cast(usize, size_u64) orelse return error.FileTooBig;

        if (size == 0) return .{ .data = "", .file = file, .mapping = null };

        const mapping = try File.MemoryMap.create(io, file, .{
            .len = size,
            .protection = .{ .read = true },
        });

        return .{
            .data = mapping.memory[0..size],
            .file = file,
            .mapping = mapping,
        };
    }

    pub fn close(self: *FileReader, io: Io) void {
        if (self.mapping) |*mm| mm.destroy(io);
        self.file.close(io);
        self.* = undefined;
    }

    pub fn lines(self: FileReader) LineIterator {
        return .{ .rest = self.data };
    }
};

pub const LineIterator = struct {
    rest: []const u8,

    pub fn next(it: *LineIterator) ?[]const u8 {
        if (it.rest.len == 0) return null;
        const nl = std.mem.indexOfScalar(u8, it.rest, '\n') orelse {
            const line = it.rest;
            it.rest = it.rest[it.rest.len..];
            return stripCr(line);
        };
        const line = it.rest[0..nl];
        it.rest = it.rest[nl + 1 ..];
        return stripCr(line);
    }

    fn stripCr(line: []const u8) []const u8 {
        if (line.len > 0 and line[line.len - 1] == '\r') return line[0 .. line.len - 1];
        return line;
    }
};
