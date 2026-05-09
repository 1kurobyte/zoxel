pub const Block = struct {
    type: enum(u8) {},
    id: u8,

    // chunks are 16x16x16
    pos: struct { x: u4, y: u4, z: u4 },
};
