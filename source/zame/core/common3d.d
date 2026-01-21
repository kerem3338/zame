module zame.core.common3d;

import zame;
import std.math;

Vec3 rotate_xz(Vec3 v, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return Vec3(v.x * c - v.z * s, v.y, v.x * s + v.z * c);
}

Vec3 rotate_yz(Vec3 v, float angle) {
    float c = cos(angle * 0.7f);
    float s = sin(angle * 0.7f);
    return Vec3(v.x, v.y * c - v.z * s, v.y * s + v.z * c);
}

Vec3 translate_z(Vec3 v, float dz) {
    return Vec3(v.x, v.y, v.z + dz);
}

Point project(Vec3 v, uint width, uint height) {
    float px = v.x / v.z;
    float py = v.y / v.z;
    return Point(cast(int)((px + 1.0f) / 2.0f * width),
                 cast(int)((1.0f - (py + 1.0f) / 2.0f) * height));
}

Vec3[4] make3DQuad(float width, float height, Vec3 center) {
    float hw = width * 0.5f;
    float hh = height * 0.5f;
    return [
        Vec3(center.x - hw, center.y - hh, center.z), // top-left
        Vec3(center.x + hw, center.y - hh, center.z), // top-right
        Vec3(center.x + hw, center.y + hh, center.z), // bottom-right
        Vec3(center.x - hw, center.y + hh, center.z)  // bottom-left
    ];
}

Point[] spinImage3D(Vec3[4] quad, float angleXZ, float angleYZ, float dz, uint screenWidth, uint screenHeight) {
    Point[] points;
    points.length = quad.length;

    foreach(i, v; quad) {
        Vec3 tmp = rotate_xz(v, angleXZ);
        tmp = rotate_yz(tmp, angleYZ);
        tmp = translate_z(tmp, dz);

        points[i] = project(tmp, screenWidth, screenHeight);
    }

    return points;
}
