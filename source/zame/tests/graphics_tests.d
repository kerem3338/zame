module zame.tests.graphics_tests;

import zame.core.graphics;
import zame.core.common;

unittest {
    auto surf = new Surface(100, 100);
    assert(surf.width == 100);
    assert(surf.height == 100);
}

unittest {
    auto surf = new Surface(10, 10);
    surf.fill(Color(255, 0, 0));

    auto pixel = surf.getPixel(Point(5, 5));
    assert(pixel.r == 255);
    assert(pixel.g == 0);
    assert(pixel.b == 0);
}

unittest {
    auto surf = new Surface(10, 10);
    surf.setPixel(Point(3, 3), Color(100, 150, 200));

    auto pixel = surf.getPixel(Point(3, 3));
    assert(pixel.r == 100);
    assert(pixel.g == 150);
    assert(pixel.b == 200);
}

unittest {
    auto src = Color(255, 0, 0, 128);
    auto dst = Color(0, 0, 255, 255);
    auto result = alphaBlend(src, dst);

    assert(result.r > 0);
    assert(result.b > 0);
}

unittest {
    auto src = new Surface(10, 10);
    src.fill(Color(255, 0, 0));

    auto scaled = scaleSurface(src, 20, 20);
    assert(scaled.width == 20);
    assert(scaled.height == 20);

    auto pixel = scaled.getPixel(Point(10, 10));
    assert(pixel.r == 255);
}

unittest {
    auto surf = new Surface(50, 50);
    IGraphics g = new SoftwareGraphics(surf);

    g.clear(Color(0, 0, 0, 255));
    assert(surf.getPixel(Point(0, 0)) == Color(0, 0, 0, 255));

    g.drawRect(Rect(10, 10, 20, 20), Color(255, 255, 0, 255));
    assert(surf.getPixel(Point(15, 15)) == Color(255, 255, 0, 255));
    assert(surf.getPixel(Point(5, 5)) == Color(0, 0, 0, 255));

    g.drawPoint(Point(2, 2), Color(0, 255, 0, 255));
    assert(surf.getPixel(Point(2, 2)) == Color(0, 255, 0, 255));

    g.setClip(Rect(0, 0, 5, 5));
    assert(g.isClipping());
    assert(g.getClipRect() == Rect(0, 0, 5, 5));
    g.resetClip();
    assert(!g.isClipping());
}
