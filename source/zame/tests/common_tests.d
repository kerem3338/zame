module zame.tests.common_tests;

import zame.core.common;

unittest {
    // Test Vec2 creation
    auto v = Vec2(3.0f, 4.0f);
    assert(v.x == 3.0f);
    assert(v.y == 4.0f);
}

unittest {
    // Test Vec2 length
    auto v = Vec2(3.0f, 4.0f);
    assert(v.length() == 5.0f);
}

unittest {
    // Test Vec2 .normalized
    auto v = Vec2(3.0f, 4.0f);
    auto n = v.normalized();
    assert(n.x == 0.6f);
    assert(n.y == 0.8f);
}

unittest {
    // Test Vec2 .zero
    auto v = Vec2.zero();
    assert(v.x == 0.0f);
    assert(v.y == 0.0f);
}

unittest {
    // Test Color creation
    auto c = Color(255, 128, 64, 200);
    assert(c.r == 255);
    assert(c.g == 128);
    assert(c.b == 64);
    assert(c.a == 200);
}

unittest {
    // Test Rect intersection
    auto r1 = Rect(0, 0, 10, 10);
    auto r2 = Rect(5, 5, 10, 10);
    auto r3 = Rect(20, 20, 10, 10);
    
    assert(r1.intersects(r2));
    assert(!r1.intersects(r3));
}
