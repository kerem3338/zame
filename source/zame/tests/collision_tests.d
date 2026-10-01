module zame.tests.collision_tests;

import zame.core.common;
import zame.core.graphics;
import zame.core.collision;

unittest {
    CollisionFilter f1 = CollisionFilter(0x0001, 0x0002);
    CollisionFilter f2 = CollisionFilter(0x0002, 0x0001);
    CollisionFilter f3 = CollisionFilter(0x0004, 0x0004);

    assert(f1.shouldCollide(f2));
    assert(!f1.shouldCollide(f3));
}

unittest {
    auto boxA = CollisionAABB(0, 0, 10, 10);
    auto boxB = CollisionAABB(5, 0, 10, 10);
    auto boxC = CollisionAABB(20, 20, 10, 10);

    assert(boxA.intersects(boxB));
    assert(!boxA.intersects(boxC));

    auto info = boxA.getResponse(boxB);
    assert(info.hasCollision);
    assert(info.penetrationDepth == 5.0f);
}

unittest {
    auto maskA = new PixelMask(10, 10);
    auto maskB = new PixelMask(10, 10);

    maskA.set(5, 5, true);
    maskB.set(0, 0, true);

    auto hit1 = maskA.overlap(maskB, Point(5, 5));
    assert(!hit1.isNull);
    assert(hit1.get == Point(5, 5));

    auto hit2 = maskA.overlap(maskB, Point(0, 0));
    assert(hit2.isNull);

    assert(maskA.overlapArea(maskB, Point(5, 5)) == 1);
}

unittest {
    auto surfA = new Surface(8, 8);
    surfA.fill(Color(255, 0, 0, 255));

    auto surfB = new Surface(8, 8);
    surfB.fill(Color(0, 255, 0, 255));

    auto colA = new Collider2D(Point(0, 0), surfA);
    auto colB = new Collider2D(Point(4, 4), surfB);
    auto colC = new Collider2D(Point(20, 20), surfB);

    auto infoAB = colA.checkCollision(colB);
    assert(infoAB.hasCollision);

    auto infoAC = colA.checkCollision(colC);
    assert(!infoAC.hasCollision);
}
