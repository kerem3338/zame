module zame.tests.common_tests;

import std.conv : to;
import zame.core.common;

unittest {
	Vec2 v = Vec2(10.5f, 20.3f);
	Point p = v.to!Point;
	assert(p.x == 10 && p.y == 20);

	Point p2 = cast(Point)v;
	assert(p2.x == 10 && p2.y == 20);

	Point p3 = Point(15, 25);
	Vec2 v2 = p3.to!Vec2;
	assert(v2.x == 15.0f && v2.y == 25.0f);

	Vec2 v3 = cast(Vec2)p3;
	assert(v3.x == 15.0f && v3.y == 25.0f);
}
