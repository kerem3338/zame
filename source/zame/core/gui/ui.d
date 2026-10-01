module zame.core.gui.ui;

import std.format : format;
import std.traits : isNumeric;
import zame.core.common;
import zame.core.graphics;

enum float POINTS_PER_INCH = 72.0f;
enum float CSS_DPI = 96.0f;
enum float PT_TO_PX = CSS_DPI / POINTS_PER_INCH;

private float fmin(float a, float b) pure nothrow @nogc { return a < b ? a : b; }
private float fmax(float a, float b) pure nothrow @nogc { return a > b ? a : b; }
private float fclamp(float v, float minV, float maxV) pure nothrow @nogc {
    if (v < minV) return minV;
    if (v > maxV) return maxV;
    return v;
}

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

enum UnitType {
    px,
    rem,
    em,
    pct,
    vw,
    vh,
    vmin,
    vmax,
    pt
}

enum ExprOp {
    none,
    add,
    sub,
    mul,
    div,
    min,
    max,
    clamp
}

struct UIContext {
    float rootFontSize = 16.0f;
    float parentFontSize = 16.0f;
    float parentWidth = 0.0f;
    float parentHeight = 0.0f;
    float viewportWidth = 1920.0f;
    float viewportHeight = 1080.0f;
    float scale = 1.0f;

    this(const UISystem ui, float parentW = 0, float parentH = 0) {
        if (ui !is null) {
            this.rootFontSize = ui.baseFont * ui.minScale();
            this.parentFontSize = this.rootFontSize;
            this.parentWidth = parentW;
            this.parentHeight = parentH;
            this.viewportWidth = ui.currentWidth;
            this.viewportHeight = ui.currentHeight;
            this.scale = ui.minScale();
        }
    }
}

struct Length {
    ExprOp op = ExprOp.none;
    float value = 0.0f;
    UnitType unit = UnitType.px;
    Length[] args;
    float scalar = 1.0f;

    static Length literal(float val, UnitType u) {
        Length l;
        l.op = ExprOp.none;
        l.value = val;
        l.unit = u;
        return l;
    }

    static Length px(float val) { return literal(val, UnitType.px); }
    static Length rem(float val) { return literal(val, UnitType.rem); }
    static Length em(float val) { return literal(val, UnitType.em); }
    static Length pct(float val) { return literal(val, UnitType.pct); }
    static Length percent(float val) { return literal(val, UnitType.pct); }
    static Length vw(float val) { return literal(val, UnitType.vw); }
    static Length vh(float val) { return literal(val, UnitType.vh); }
    static Length vmin(float val) { return literal(val, UnitType.vmin); }
    static Length vmax(float val) { return literal(val, UnitType.vmax); }
    static Length pt(float val) { return literal(val, UnitType.pt); }

    Length opBinary(string opSymbol : "+")(Length rhs) const {
        Length l;
        l.op = ExprOp.add;
        l.args = [cast()this, rhs];
        return l;
    }

    Length opBinary(string opSymbol : "-")(Length rhs) const {
        Length l;
        l.op = ExprOp.sub;
        l.args = [cast()this, rhs];
        return l;
    }

    Length opBinary(string opSymbol : "*", T)(T factor) const if (isNumeric!T) {
        Length l;
        l.op = ExprOp.mul;
        l.args = [cast()this];
        l.scalar = cast(float)factor;
        return l;
    }

    Length opBinaryRight(string opSymbol : "*", T)(T factor) const if (isNumeric!T) {
        return this * factor;
    }

    Length opBinary(string opSymbol : "/", T)(T factor) const if (isNumeric!T) {
        Length l;
        l.op = ExprOp.div;
        l.args = [cast()this];
        l.scalar = cast(float)factor;
        return l;
    }

    float toPx(const UIContext ctx, float parentDim = 0.0f) const {
        final switch (op) {
            case ExprOp.none:
                final switch (unit) {
                    case UnitType.px:
                        return value;
                    case UnitType.rem:
                        return value * ctx.rootFontSize;
                    case UnitType.em:
                        return value * ctx.parentFontSize;
                    case UnitType.pct:
                        float refDim = (parentDim > 0) ? parentDim : ctx.parentWidth;
                        return (value / 100.0f) * refDim;
                    case UnitType.vw:
                        return (value / 100.0f) * ctx.viewportWidth;
                    case UnitType.vh:
                        return (value / 100.0f) * ctx.viewportHeight;
                    case UnitType.vmin:
                        return (value / 100.0f) * fmin(ctx.viewportWidth, ctx.viewportHeight);
                    case UnitType.vmax:
                        return (value / 100.0f) * fmax(ctx.viewportWidth, ctx.viewportHeight);
                    case UnitType.pt:
                        return value * PT_TO_PX;
                }
            case ExprOp.add:
                float sum = 0;
                foreach (ref a; args) sum += a.toPx(ctx, parentDim);
                return sum;
            case ExprOp.sub:
                if (args.length == 0) return 0;
                float diff = args[0].toPx(ctx, parentDim);
                foreach (ref a; args[1 .. $]) diff -= a.toPx(ctx, parentDim);
                return diff;
            case ExprOp.mul:
                if (args.length == 0) return 0;
                return args[0].toPx(ctx, parentDim) * scalar;
            case ExprOp.div:
                if (args.length == 0 || scalar == 0) return 0;
                return args[0].toPx(ctx, parentDim) / scalar;
            case ExprOp.min:
                if (args.length == 0) return 0;
                float minVal = args[0].toPx(ctx, parentDim);
                foreach (ref a; args[1 .. $]) {
                    minVal = fmin(minVal, a.toPx(ctx, parentDim));
                }
                return minVal;
            case ExprOp.max:
                if (args.length == 0) return 0;
                float maxVal = args[0].toPx(ctx, parentDim);
                foreach (ref a; args[1 .. $]) {
                    maxVal = fmax(maxVal, a.toPx(ctx, parentDim));
                }
                return maxVal;
            case ExprOp.clamp:
                if (args.length < 3) return (args.length > 0) ? args[0].toPx(ctx, parentDim) : 0;
                float minV = args[0].toPx(ctx, parentDim);
                float val = args[1].toPx(ctx, parentDim);
                float maxV = args[2].toPx(ctx, parentDim);
                return fclamp(val, minV, maxV);
        }
    }

    int toIntPx(const UIContext ctx, float parentDim = 0.0f) const {
        return cast(int)(toPx(ctx, parentDim) + 0.5f);
    }

    float toPx(const UISystem ui, float parentDim = 0.0f) const {
        return toPx(UIContext(ui, parentDim, parentDim), parentDim);
    }

    int toIntPx(const UISystem ui, float parentDim = 0.0f) const {
        return cast(int)(toPx(ui, parentDim) + 0.5f);
    }

    string toString() const {
        final switch (op) {
            case ExprOp.none:
                return format("%g%s", value, unitToString(unit));
            case ExprOp.add:
                return format("(%s + %s)", args.length > 0 ? args[0].toString() : "", args.length > 1 ? args[1].toString() : "");
            case ExprOp.sub:
                return format("(%s - %s)", args.length > 0 ? args[0].toString() : "", args.length > 1 ? args[1].toString() : "");
            case ExprOp.mul:
                return format("(%s * %g)", args.length > 0 ? args[0].toString() : "", scalar);
            case ExprOp.div:
                return format("(%s / %g)", args.length > 0 ? args[0].toString() : "", scalar);
            case ExprOp.min:
                string s = "min(";
                foreach (i, ref a; args) {
                    if (i > 0) s ~= ", ";
                    s ~= a.toString();
                }
                return s ~ ")";
            case ExprOp.max:
                string s = "max(";
                foreach (i, ref a; args) {
                    if (i > 0) s ~= ", ";
                    s ~= a.toString();
                }
                return s ~ ")";
            case ExprOp.clamp:
                return format("clamp(%s, %s, %s)",
                    args.length > 0 ? args[0].toString() : "",
                    args.length > 1 ? args[1].toString() : "",
                    args.length > 2 ? args[2].toString() : "");
        }
    }

    private static string unitToString(UnitType u) {
        final switch (u) {
            case UnitType.px: return "px";
            case UnitType.rem: return "rem";
            case UnitType.em: return "em";
            case UnitType.pct: return "%";
            case UnitType.vw: return "vw";
            case UnitType.vh: return "vh";
            case UnitType.vmin: return "vmin";
            case UnitType.vmax: return "vmax";
            case UnitType.pt: return "pt";
        }
    }
}

Length px(T)(T v) if (isNumeric!T) { return Length.px(cast(float)v); }
Length rem(T)(T v) if (isNumeric!T) { return Length.rem(cast(float)v); }
Length em(T)(T v) if (isNumeric!T) { return Length.em(cast(float)v); }
Length pct(T)(T v) if (isNumeric!T) { return Length.pct(cast(float)v); }
Length percent(T)(T v) if (isNumeric!T) { return Length.pct(cast(float)v); }
Length vw(T)(T v) if (isNumeric!T) { return Length.vw(cast(float)v); }
Length vh(T)(T v) if (isNumeric!T) { return Length.vh(cast(float)v); }
Length vmin(T)(T v) if (isNumeric!T) { return Length.vmin(cast(float)v); }
Length vmax(T)(T v) if (isNumeric!T) { return Length.vmax(cast(float)v); }
Length pt(T)(T v) if (isNumeric!T) { return Length.pt(cast(float)v); }

Length min(Length a, Length b) {
    Length l;
    l.op = ExprOp.min;
    l.args = [a, b];
    return l;
}

Length min(Length[] args...) {
    Length l;
    l.op = ExprOp.min;
    l.args = args.dup;
    return l;
}

Length max(Length a, Length b) {
    Length l;
    l.op = ExprOp.max;
    l.args = [a, b];
    return l;
}

Length max(Length[] args...) {
    Length l;
    l.op = ExprOp.max;
    l.args = args.dup;
    return l;
}

Length clamp(Length minVal, Length val, Length maxVal) {
    Length l;
    l.op = ExprOp.clamp;
    l.args = [minVal, val, maxVal];
    return l;
}

Length calc(Length expr) {
    return expr;
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

    void updateSize(Size size) {
        updateSize(size.w, size.h);
    }
    
    float scaleX() const { return cast(float)currentWidth / designWidth; }
    float scaleY() const { return cast(float)currentHeight / designHeight; }
    float minScale() const { return fmin(scaleX(), scaleY()); }

    // Integer pixel values (backward-compatible)
    int rem(float value) const { return cast(int)(value * baseFont * minScale() + 0.5f); }
    int vw(float percent) const { return cast(int)(percent * currentWidth / 100.0f); }
    int vh(float percent) const { return cast(int)(percent * currentHeight / 100.0f); }
    int fontSize(float remValue) const { return rem(remValue); }

    // Length construction
    Length px(T)(T v) const if (isNumeric!T) { return Length.px(cast(float)v); }
    Length em(T)(T v) const if (isNumeric!T) { return Length.em(cast(float)v); }
    Length pct(T)(T v) const if (isNumeric!T) { return Length.pct(cast(float)v); }
    Length percent(T)(T v) const if (isNumeric!T) { return Length.pct(cast(float)v); }
    Length vmin(T)(T v) const if (isNumeric!T) { return Length.vmin(cast(float)v); }
    Length vmax(T)(T v) const if (isNumeric!T) { return Length.vmax(cast(float)v); }
    Length pt(T)(T v) const if (isNumeric!T) { return Length.pt(cast(float)v); }

    Length min(Length a, Length b) const { return .min(a, b); }
    Length min(Length[] args...) const { return .min(args); }
    Length max(Length a, Length b) const { return .max(a, b); }
    Length max(Length[] args...) const { return .max(args); }
    Length clamp(Length minVal, Length val, Length maxVal) const { return .clamp(minVal, val, maxVal); }
    Length calc(Length expr) const { return expr; }

    UIContext createContext(float parentW = 0, float parentH = 0) const {
        return UIContext(this, parentW, parentH);
    }

    float resolve(Length len, float parentDim = 0) const {
        return len.toPx(this, parentDim);
    }

    int resolveInt(Length len, float parentDim = 0) const {
        return len.toIntPx(this, parentDim);
    }

    Surface scale(Surface src, float factor) const {
        float s = factor * minScale();
        return scaleSurface(src, cast(int)(src.width * s), cast(int)(src.height * s));
    }

    Surface scaleToRem(Surface src, float wRem, float hRem) const {
        return scaleSurface(src, resolveInt(Length.rem(wRem)), resolveInt(Length.rem(hRem)));
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
