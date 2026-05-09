// 0 4  8 12
// 1 5  9 13
// 2 6 10 14
// 3 7 11 15

pub const Mat4 = [16]f32;

pub fn identity() Mat4 {
    var m: Mat4 = @splat(0);
    inline for (0..4) |i| {
        m[5 * i] = 1;
    }
    return m;
}

pub fn mul(a: Mat4, b: Mat4) Mat4 {
    var r: Mat4 = undefined;
    inline for (0..4) |col| inline for (0..4) |row| {
        var sum: f32 = 0;
        inline for (0..4) |k| sum += a[k * 4 + row] * b[col * 4 + k];
        r[col * 4 + row] = sum;
    };
    return r;
}

pub fn translate(x: f32, y: f32, z: f32) Mat4 {
    var m = identity();
    m[12] = x;
    m[13] = y;
    m[14] = z;
    return m;
}

pub fn rotateX(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    var m: Mat4 = @splat(0);
    // 1 0  0 0
    // 0 c -s 0
    // 0 s  c 0
    // 0 0  0 1
    m[0] = 1;
    m[5] = c;
    m[6] = s;
    m[9] = -s;
    m[10] = c;
    m[15] = 1;
    return m;
}

pub fn rotateY(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    var m: Mat4 = @splat(0);
    //  c 0 s 0
    //  0 1 0 0
    // -s 0 c 0
    //  0 0 0 1
    m[0] = c;
    m[2] = -s;
    m[5] = 1;
    m[8] = s;
    m[10] = c;
    m[15] = 1;
    return m;
}

pub fn rotateZ(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    var m: Mat4 = @splat(0);
    // c -s 0 0
    // s  c 0 0
    // 0  0 1 0
    // 0  0 0 1
    m[0] = c;
    m[1] = s;
    m[4] = -s;
    m[5] = c;
    m[10] = 1;
    m[15] = 1;
    return m;
}

pub fn perspective(fov_y_radians: f32, aspect: f32, near: f32, far: f32) Mat4 {
    const f = 1.0 / @tan(fov_y_radians / 2.0);
    var m: Mat4 = @splat(0);
    m[0] = f / aspect;
    m[5] = -f;
    m[10] = far / (near - far);
    m[11] = -1;
    m[14] = (near * far) / (near - far);
    return m;
}
