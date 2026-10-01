module zame.core.collision;

import std.math : abs;
import std.algorithm.comparison : min, max;
import std.format   : format;
import std.typecons : Nullable;
import zame.core.common;
import zame.core.graphics;

struct CollisionFilter {
    uint categoryBits = 0x0001;
    uint maskBits     = 0xFFFF;
    int  groupIndex   = 0;

    bool shouldCollide(const CollisionFilter other) const {
        if (groupIndex != 0 && groupIndex == other.groupIndex)
            return groupIndex > 0;

        return (categoryBits & other.maskBits) != 0 &&
               (other.categoryBits & maskBits) != 0;
    }
}

struct CollisionInfo {
    bool   hasCollision;
    Vec2   normal;
    float  penetrationDepth;
    Point  contactPoint;

    string toString() const {
        if (!hasCollision) return "CollisionInfo(none)";
        return format("CollisionInfo(normal=%s, depth=%.2f, point=%s)",
            normal, penetrationDepth, contactPoint);
    }
}

struct CollisionAABB {
    Rect bounds;

    this(int x, int y, int width, int height) {
        bounds = Rect(x, y, width, height);
    }

    this(Rect rect) {
        bounds = rect;
    }

    this(Vec2 pos, Size size) {
        bounds = Rect(cast(int)pos.x, cast(int)pos.y, cast(int)size.w, cast(int)size.h);
    }

    this(Point pos, Size size) {
        bounds = Rect(pos.x, pos.y, cast(int)size.w, cast(int)size.h);
    }

    @property int x() const { return bounds.x; }
    @property int y() const { return bounds.y; }
    @property int width() const { return bounds.w; }
    @property int height() const { return bounds.h; }

    @property Point center() const { return bounds.center(); }
    @property Point topLeft() const { return bounds.topLeft(); }
    @property Point bottomRight() const { return bounds.bottomRight(); }

    bool intersects(const CollisionAABB other) const {
        return bounds.intersects(other.bounds);
    }

    bool contains(Point p) const {
        return bounds.contains(p);
    }

    bool contains(Vec2 p) const {
        return p.x >= bounds.x && p.x < bounds.x + bounds.w &&
               p.y >= bounds.y && p.y < bounds.y + bounds.h;
    }

    Rect getIntersection(const CollisionAABB other) const {
        int ix1 = max(bounds.x, other.bounds.x);
        int iy1 = max(bounds.y, other.bounds.y);
        int ix2 = min(bounds.x + bounds.w, other.bounds.x + other.bounds.w);
        int iy2 = min(bounds.y + bounds.h, other.bounds.y + other.bounds.h);

        if (ix1 < ix2 && iy1 < iy2)
            return Rect(ix1, iy1, ix2 - ix1, iy2 - iy1);
        return Rect(0, 0, 0, 0);
    }

    CollisionInfo getResponse(const CollisionAABB staticTarget) const {
        CollisionInfo info;
        if (!intersects(staticTarget)) return info;

        float overlapX1 = (bounds.x + bounds.w) - staticTarget.bounds.x;
        float overlapX2 = (staticTarget.bounds.x + staticTarget.bounds.w) - bounds.x;
        float overlapY1 = (bounds.y + bounds.h) - staticTarget.bounds.y;
        float overlapY2 = (staticTarget.bounds.y + staticTarget.bounds.h) - bounds.y;

        float minOverlapX = overlapX1 < overlapX2 ? overlapX1 : -overlapX2;
        float minOverlapY = overlapY1 < overlapY2 ? overlapY1 : -overlapY2;

        info.hasCollision = true;
        if (abs(minOverlapX) < abs(minOverlapY)) {
            info.penetrationDepth = abs(minOverlapX);
            info.normal = minOverlapX > 0 ? Vec2(-1.0f, 0.0f) : Vec2(1.0f, 0.0f);
        } else {
            info.penetrationDepth = abs(minOverlapY);
            info.normal = minOverlapY > 0 ? Vec2(0.0f, -1.0f) : Vec2(0.0f, 1.0f);
        }

        info.contactPoint = Point(
            bounds.x + bounds.w / 2,
            bounds.y + bounds.h / 2
        );
        return info;
    }
}

final class PixelMask {
    uint width;
    uint height;

    private ulong[] _words;
    private size_t  _wordsPerRow;

    this(uint width, uint height) {
        this.width = width;
        this.height = height;
        this._wordsPerRow = (width + 63) / 64;
        this._words.length = _wordsPerRow * height;
    }

    static PixelMask fromSurface(const Surface surface, ubyte alphaThreshold = 1) {
        if (surface is null) return null;

        auto mask = new PixelMask(surface.width, surface.height);
        for (int y = 0; y < cast(int)surface.height; y++) {
            for (int x = 0; x < cast(int)surface.width; x++) {
                Color c = (cast(Surface)surface).getPixel(Point(x, y));
                if (c.a >= alphaThreshold) {
                    mask.set(x, y, true);
                }
            }
        }
        return mask;
    }

    bool get(int x, int y) const {
        if (x < 0 || y < 0 || x >= cast(int)width || y >= cast(int)height)
            return false;

        size_t wordIdx = y * _wordsPerRow + (x / 64);
        size_t bitIdx  = x % 64;
        return (_words[wordIdx] & (1UL << bitIdx)) != 0;
    }

    void set(int x, int y, bool solid) {
        if (x < 0 || y < 0 || x >= cast(int)width || y >= cast(int)height)
            return;

        size_t wordIdx = y * _wordsPerRow + (x / 64);
        size_t bitIdx  = x % 64;
        if (solid)
            _words[wordIdx] |= (1UL << bitIdx);
        else
            _words[wordIdx] &= ~(1UL << bitIdx);
    }

    void clear() {
        _words[] = 0;
    }

    void fill() {
        _words[] = ulong.max;
    }

    Nullable!Point overlap(const PixelMask other, Point offset) const {
        Nullable!Point result;
        if (other is null) return result;

        int startY = max(0, offset.y);
        int endY   = min(cast(int)height, offset.y + cast(int)other.height);

        int startX = max(0, offset.x);
        int endX   = min(cast(int)width, offset.x + cast(int)other.width);

        for (int y = startY; y < endY; y++) {
            int otherY = y - offset.y;
            for (int x = startX; x < endX; x++) {
                int otherX = x - offset.x;
                if (get(x, y) && other.get(otherX, otherY)) {
                    result = Point(x, y);
                    return result;
                }
            }
        }
        return result;
    }

    uint overlapArea(const PixelMask other, Point offset) const {
        if (other is null) return 0;

        int startY = max(0, offset.y);
        int endY   = min(cast(int)height, offset.y + cast(int)other.height);

        int startX = max(0, offset.x);
        int endX   = min(cast(int)width, offset.x + cast(int)other.width);

        uint count = 0;
        for (int y = startY; y < endY; y++) {
            int otherY = y - offset.y;
            for (int x = startX; x < endX; x++) {
                int otherX = x - offset.x;
                if (get(x, y) && other.get(otherX, otherY)) {
                    count++;
                }
            }
        }
        return count;
    }
}

class Collider2D {
    Point           position;
    Size            size;
    CollisionFilter filter;
    PixelMask       mask;
    bool            isTrigger = false;

    this(Point position, Size size) {
        this.position = position;
        this.size     = size;
    }

    this(Point position, Surface surface) {
        this.position = position;
        if (surface !is null) {
            this.size = Size(surface.width, surface.height);
            this.mask = PixelMask.fromSurface(surface);
        }
    }

    CollisionAABB getAABB() const {
        return CollisionAABB(position, size);
    }

    CollisionInfo checkCollision(const Collider2D other) const {
        CollisionInfo info;
        if (other is null || other is this) return info;

        if (!filter.shouldCollide(other.filter)) return info;

        CollisionAABB aabbA = getAABB();
        CollisionAABB aabbB = other.getAABB();

        if (!aabbA.intersects(aabbB)) return info;

        if (mask !is null && other.mask !is null) {
            Point offset = Point(other.position.x - position.x, other.position.y - position.y);
            auto overlapPt = mask.overlap(other.mask, offset);

            if (overlapPt.isNull) return info;

            info.hasCollision     = true;
            info.contactPoint     = Point(position.x + overlapPt.get.x, position.y + overlapPt.get.y);
            info.penetrationDepth = 1.0f;
            return info;
        }

        return aabbA.getResponse(aabbB);
    }
}
