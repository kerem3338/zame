module zame.tests.graphics_tests;

import zame.core.graphics;
import zame.core.common;

unittest {
    // Test Surface creation
    auto surf = new Surface(100, 100);
    assert(surf.width == 100);
    assert(surf.height == 100);
}

unittest {
    // Test Surface .fill
    auto surf = new Surface(10, 10);
    surf.fill(Color(255, 0, 0));
    
    auto pixel = surf.getPixel(Point(5, 5));
    assert(pixel.r == 255);
    assert(pixel.g == 0);
    assert(pixel.b == 0);
}

unittest {
    // Test Surface .setPixel/.getPixel
    auto surf = new Surface(10, 10);
    surf.setPixel(Point(3, 3), Color(100, 150, 200));
    
    auto pixel = surf.getPixel(Point(3, 3));
    assert(pixel.r == 100);
    assert(pixel.g == 150);
    assert(pixel.b == 200);
}

unittest {
    // Test alpha blending
    auto src = Color(255, 0, 0, 128);
    auto dst = Color(0, 0, 255, 255);
    auto result = alphaBlend(src, dst);
    
    // Result should be a blend of red and blue
    assert(result.r > 0);
    assert(result.b > 0);
}

unittest {
    // Test scaleSurface
    auto src = new Surface(10, 10);
    src.fill(Color(255, 0, 0));
    
    auto scaled = scaleSurface(src, 20, 20);
    assert(scaled.width == 20);
    assert(scaled.height == 20);
    
    auto pixel = scaled.getPixel(Point(10, 10));
    assert(pixel.r == 255);
}
