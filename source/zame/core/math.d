module zame.core.math;

import zame;
import std.math;

float distVec2(Vec2 p1, Vec2 p2)
{
	float dx = p2.x - p1.x;
	float dy = p2.y - p1.y;
	return dx * dx + dy * dy;
}


int distPoint(Point p1, Point p2)
{
    int dx = p2.x - p1.x;
    int dy = p2.y - p1.y;

    return cast(int)(
        sqrt(cast(double)(dx * dx + dy * dy)) + 0.5
    );
}
