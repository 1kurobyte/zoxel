const Block = @import("block.zig").Block;

pub const Chunk = struct {
    pos: struct { x: i64, y: i64, z: i64 },
    blocks: [16][16][16]Block, // todo compare performance with flat [4096]Block
};
