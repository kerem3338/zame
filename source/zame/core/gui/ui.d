module zame.core.gui.ui;

import std.algorithm : min, max;
import zame.core.common;
import zame.core.graphics;

struct AspectRatio {
    int w;
    int h;

    float ratio() const { return cast(float)w / h; }

    static AspectRatio ar16_9() { return AspectRatio(16, 9); }
    static AspectRatio ar4_3() { return AspectRatio(4, 3); }
    static AspectRatio ar21_9() { return AspectRatio(21, 9); }
    static AspectRatio ar1_1() { return AspectRatio(1, 1); }
    static AspectRatio ar9_16() { return AspectRatio(9, 16); }
}

class UISystem {
    int designWidth;
    int designHeight;
    int baseFont;
    int currentWidth;
    int currentHeight;

    this(int designWidth = 1920, int designHeight = 1080, int baseFont = 16) {
        this.designWidth = designWidth;
        this.designHeight = designHeight;
        this.baseFont = baseFont;
        this.currentWidth = designWidth;
        this.currentHeight = designHeight;
    }

    void updateSize(int w, int h) {
        this.currentWidth = w;
        this.currentHeight = h;
    }

    float scaleX() const { return cast(float)currentWidth / designWidth; }
    float scaleY() const { return cast(float)currentHeight / designHeight; }
    float minScale() const { return min(scaleX(), scaleY()); }

    int rem(float value) const {
        return cast(int)(value * baseFont * minScale());
    }

    int fontSize(float remValue) const {
        return rem(remValue);
    }

    Surface scale(Surface src, float factor) const {
        float s = factor * minScale();
        return scaleSurface(src, cast(int)(src.width * s), cast(int)(src.height * s));
    }

    Surface scaleToRem(Surface src, float wRem, float hRem) const {
        return scaleSurface(src, rem(wRem), rem(hRem));
    }

    int vw(float percent) const {
        return cast(int)(percent * currentWidth / 100.0f);
    }

    int vh(float percent) const {
        return cast(int)(percent * currentHeight / 100.0f);
    }

    Rect center(Rect container, int w, int h) const {
        return Rect(
            container.x + (container.w - w) / 2,
            container.y + (container.h - h) / 2,
            w, h
        );
    }

    Rect centerInWindow(int w, int h) const {
        return center(Rect(0, 0, currentWidth, currentHeight), w, h);
    }

    Rect below(Rect other, int h, int spacing = 0, int w = -1) const {
        return Rect(
            other.x,
            other.y + other.h + spacing,
            (w == -1) ? other.w : w,
            h
        );
    }

    Rect above(Rect other, int h, int spacing = 0, int w = -1) const {
        return Rect(
            other.x,
            other.y - h - spacing,
            (w == -1) ? other.w : w,
            h
        );
    }

    Rect rightOf(Rect other, int w, int spacing = 0, int h = -1) const {
        return Rect(
            other.x + other.w + spacing,
            other.y,
            w,
            (h == -1) ? other.h : h
        );
    }

    Rect leftOf(Rect other, int w, int spacing = 0, int h = -1) const {
        return Rect(
            other.x - w - spacing,
            other.y,
            w,
            (h == -1) ? other.h : h
        );
    }

    Rect inset(Rect r, int t, int r_, int b, int l) const {
        return Rect(
            r.x + l,
            r.y + t,
            r.w - l - r_,
            r.h - t - b
        );
    }

    Rect fill(Rect container, int margin = 0) const {
        return inset(container, margin, margin, margin, margin);
    }

    Rect fit(Rect container, AspectRatio ar) const {
        float containerRatio = cast(float)container.w / container.h;
        float targetRatio = ar.ratio();

        int w, h;
        if (containerRatio > targetRatio) {
            h = container.h;
            w = cast(int)(h * targetRatio);
        } else {
            w = container.w;
            h = cast(int)(w / targetRatio);
        }

        return center(container, w, h);
    }
}
