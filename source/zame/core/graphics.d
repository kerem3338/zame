module zame.core.graphics;

import std.math;
import std.conv;
import std.range;
import std.format;
import std.algorithm;
import zame.core.common;
import std.stdio;
import core.stdc.string : memcpy;

enum Colors: Color {
	transparent = Color(255,255,255,0),
	black = Color(0, 0, 0),
	white = Color(255, 255, 255),
	red = Color(255, 0 , 0),
	green = Color(0, 255, 0),
	blue = Color(0, 0, 255),
	darkYellow = Color(127, 127, 0),
	yellow = Color(255, 255, 0),
	orange = Color(255, 165, 0),
	purple = Color(128, 0, 128),
	cyan = Color(0, 255, 255),
	gray = Color(127, 127, 127),
	darkGray = Color(42, 42, 42),
	antiqueWhite = Color(255, 239, 219)
}

class Surface {
	uint width;
	uint height;
	private Color[] data;
	private Rect clipRect;
	private bool useClip = false;

	@property @nogc nothrow inout(Color)[] rawData() inout
	{
		return data;
	}

	this(uint width, uint height) {
		this.resize(width,height);
	}

	this(Size size) {
		this(size.w, size.h);
	}

	/// copy constructor
	this(const Surface other) {
		this.width = other.width;
		this.height = other.height;
		this.data = other.data.dup;
		this.clipRect = other.clipRect;
		this.useClip = other.useClip;
	}

	/// deep copy of the surface
	@property Surface dup() const {
		return new Surface(this);
	}

	void resize(uint width, uint height) {
		this.width = width;
		this.height = height;
		this.data = new Color[this.width*this.height];
	}

	void fill(Color fillColor) {
		if (data.length == 0) return;
		data[] = fillColor;
	}

	bool isValidPoint(Point where) {
		return where.x >= 0 && where.y >= 0 && where.x < width && where.y < height;
	}

	Color getPixel(Point where) {
		if (!isValidPoint(where)) return Color(0,0,0);
		return data[where.y * this.width + where.x];
	}

	void setPixel(Point where, Color color) {
		data[where.y * this.width + where.x] = color;
	}

	void setPixelIndex(uint whereIndex, Color color) {
		if (whereIndex > data.length) return;
		data[whereIndex] = color;
	}

	@property @nogc nothrow Color getPixelUnchecked(uint x, uint y) const {
		return data[cast(size_t)y * width + x];
	}

	@nogc nothrow void setPixelUnchecked(uint x, uint y, Color color) {
		data[cast(size_t)y * width + x] = color;
	}

	void setAlpha(ubyte alpha) {
		foreach (ref c; data) {
			c.a = alpha;
		}
	}

	void setClip(Rect rect) {
		clipRect = rect;
		useClip = true;
	}

	void resetClip() {
		useClip = false;
	}

	Rect getClipRect() const {
		return clipRect;
	}

	bool isClipping() const {
		return useClip;
	}

	void blit(Surface src, Point where) {
		blit(src, where.x, where.y);
	}

	Surface subSurface(Rect rect, Color fallBackColor = Colors.transparent) {
		Surface outSurface = new Surface(rect.w, rect.h);

		for (int y = 0; y < rect.h; y++) {
			for (int x = 0; x < rect.w; x++) {

				int srcX = rect.x + x;
				int srcY = rect.y + y;

				Color color;

				if (srcX >= 0 && srcY >= 0 &&
					srcX < cast(int)this.width && srcY < cast(int)this.height)
				{
					color = this.data[cast(size_t)srcY * this.width + cast(size_t)srcX];
				}
				else
				{
					color = fallBackColor;
				}

				outSurface.data[cast(size_t)y * rect.w + cast(size_t)x] = color;
			}
		}

		return outSurface;
	}


	void blit(Surface src, int destX, int destY, bool useAlpha = true, ubyte globalAlpha = 255) {
		if (src is null || globalAlpha == 0) return;

		int srcStartX = 0;
		int srcStartY = 0;
		int blitWidth = src.width;
		int blitHeight = src.height;

		// Clipping
		if (destX < 0) {
			srcStartX = -destX;
			blitWidth += destX;
			destX = 0;
		}
		if (destY < 0) {
			srcStartY = -destY;
			blitHeight += destY;
			destY = 0;
		}
		if (destX + blitWidth > cast(int)width) {
			blitWidth = cast(int)width - destX;
		}
		if (destY + blitHeight > cast(int)height) {
			blitHeight = cast(int)height - destY;
		}

		if (useClip) {
			if (destX < clipRect.x) {
				int diff = clipRect.x - destX;
				srcStartX += diff;
				blitWidth -= diff;
				destX = clipRect.x;
			}
			if (destY < clipRect.y) {
				int diff = clipRect.y - destY;
				srcStartY += diff;
				blitHeight -= diff;
				destY = clipRect.y;
			}
			if (destX + blitWidth > clipRect.x + clipRect.w) {
				blitWidth = (clipRect.x + clipRect.w) - destX;
			}
			if (destY + blitHeight > clipRect.y + clipRect.h) {
				blitHeight = (clipRect.y + clipRect.h) - destY;
			}
		}

		if (blitWidth <= 0 || blitHeight <= 0) return;

		Color* dstData = data.ptr;
		const(Color)* srcData = src.data.ptr;

		size_t sw = src.width;
		size_t dw = this.width;

		if (!useAlpha && globalAlpha == 255) {
			for (int y = 0; y < blitHeight; y++) {
				int sy = srcStartY + y;
				int dy = destY + y;
				size_t srcIndex = cast(size_t)sy * sw + cast(size_t)srcStartX;
				size_t dstIndex = cast(size_t)dy * dw + cast(size_t)destX;
				memcpy(&dstData[dstIndex], &srcData[srcIndex], cast(size_t)blitWidth * Color.sizeof);
			}
		} else {
			bool hasGlobalAlpha = (globalAlpha != 255);
			uint gAlpha = cast(uint)globalAlpha;

			for (int y = 0; y < blitHeight; y++) {
				int sy = srcStartY + y;
				int dy = destY + y;

				size_t srcIndex = cast(size_t)sy * sw + cast(size_t)srcStartX;
				size_t dstIndex = cast(size_t)dy * dw + cast(size_t)destX;

				const(Color)* srcRow = &srcData[srcIndex];
				Color* dstRow = &dstData[dstIndex];

				for (int x = 0; x < blitWidth; x++) {
					Color sc = srcRow[x];
					if (hasGlobalAlpha) {
						sc.a = cast(ubyte)((sc.a * gAlpha * 257) >> 16);
					}

					if (sc.a == 0) continue;
					if (sc.a == 255) {
						dstRow[x] = sc;
					} else {
						dstRow[x] = alphaBlend(sc, dstRow[x]);
					}
				}
			}
		}
	}

	void replaceColor(Color search, Color replace, bool ignoreAlpha = false) {
		foreach (ref p; data) {
			if ((ignoreAlpha ? (p.r == search.r && p.g == search.g && p.b == search.b) : (p.r == search.r && p.g == search.g && p.b == search.b && p.a == search.a))) {
				p = replace;
			}
		}
	}

	void makeColorTransparent(Color target) {
		foreach (ref p; data) {
			if (p.r == target.r && p.g == target.g && p.b == target.b) {
				p.a = 0;
			}
		}
	}

	Surface flip(bool horizontal, bool vertical) {
		Surface outSurface = new Surface(this.width, this.height);
		for (int y = 0; y < cast(int)this.height; y++) {
			for (int x = 0; x < cast(int)this.width; x++) {
				int srcX = horizontal ? (cast(int)this.width - 1 - x) : x;
				int srcY = vertical ? (cast(int)this.height - 1 - y) : y;
				outSurface.data[cast(size_t)y * this.width + cast(size_t)x] = this.data[cast(size_t)srcY * this.width + cast(size_t)srcX];
			}
		}
		return outSurface;
	}

	Point corner0() {return Point(0,0);}
	Point corner1() {return Point(width,0);}
	Point corner2() {return Point(0,height);}
	Point corner3() {return Point(width, height);}
	Size size() { return Size(width, height); }

	override string  toString() const {
		return "Surface<"~this.width.to!string~"x"~this.height.to!string~">";
	}
}

class SpriteManager {
	Rect[string] sprites;
	Surface source;

	Size gridSpriteSize;

	this(ref Surface source) {
		this.source = source;
	}

	Outcome!Surface getWithId(string id) {
		if (!(id in sprites)) {
			return failure!Surface(Result.surface_not_found, "Sprite with id '"~id~"' doesnt exists.");
			
		}

		return success!Surface(source.subSurface(sprites[id]));
	}
}

/// Common texture handle representation for hardware & software resources
interface ITexture {
	uint width() const;
	uint height() const;
	void* handle();
}

/// Abstract Graphics Rendering Contract
interface IGraphics {
	void begin();
	void end();
	void clear(Color color);

	void setClip(Rect rect);
	void resetClip();
	Rect getClipRect() const;
	bool isClipping() const;

	void drawPoint(Point p, Color color);
	void drawLine(Point p0, Point p1, Color color, int thickness = 1);
	void drawDottedLine(Point p0, Point p1, Color color, int dotLen = 5, int gapLen = 5, int thickness = 1);
	void drawRect(Rect rect, Color color);
	void drawRectOutline(Rect rect, Color color, uint thickness = 1);
	void drawCircle(Point center, int radius, Color color);
	void drawFilledCircle(Point center, int radius, Color color);
	void drawPolygon(Point[] points, Color color, int thickness = 1);
	void drawFilledPolygon(Point[] points, Color color);

	void drawSurface(Surface src, int x, int y, bool useAlpha = true, ubyte globalAlpha = 255);
	void drawSurfaceRotated(Surface src, int x, int y, float angleRadians);
	void drawSurfaceScaled(Surface src, Rect destRect);
	void drawTexture(ITexture texture, Rect srcRect, Rect destRect, Color tint = Colors.white);
}

/// Portable Software Graphics Backend rendering directly into a Surface
class SoftwareGraphics : IGraphics {
	Surface target;

	this(Surface target = null) {
		this.target = target;
	}

	void setTarget(Surface surface) {
		this.target = surface;
	}

	void begin() {}
	void end() {}

	void clear(Color color) {
		if (target !is null) target.fill(color);
	}

	void setClip(Rect rect) {
		if (target !is null) target.setClip(rect);
	}

	void resetClip() {
		if (target !is null) target.resetClip();
	}

	Rect getClipRect() const {
		return target !is null ? target.getClipRect() : Rect.init;
	}

	bool isClipping() const {
		return target !is null ? target.isClipping() : false;
	}

	void drawPoint(Point p, Color color) {
		if (target !is null && target.isValidPoint(p)) {
			target.setPixel(p, color);
		}
	}

	void drawLine(Point p0, Point p1, Color color, int thickness = 1) {
		if (target !is null) {
			Graphics.drawLine(target, color, p0, p1, thickness);
		}
	}

	void drawDottedLine(Point p0, Point p1, Color color, int dotLen = 5, int gapLen = 5, int thickness = 1) {
		if (target !is null) {
			Graphics.drawDottedLine(target, color, p0, p1, dotLen, gapLen, thickness);
		}
	}

	void drawRect(Rect rect, Color color) {
		if (target !is null) {
			Graphics.drawRect(target, color, rect);
		}
	}

	void drawRectOutline(Rect rect, Color color, uint thickness = 1) {
		if (target !is null) {
			Graphics.drawRectOutline(target, color, rect, thickness);
		}
	}

	void drawCircle(Point center, int radius, Color color) {
		if (target !is null) {
			Graphics.drawCircle(target, color, center, radius);
		}
	}

	void drawFilledCircle(Point center, int radius, Color color) {
		if (target !is null) {
			Graphics.drawFilledCircle(target, color, center, radius);
		}
	}

	void drawPolygon(Point[] points, Color color, int thickness = 1) {
		if (target !is null) {
			Graphics.drawPolygon(target, color, points, thickness);
		}
	}

	void drawFilledPolygon(Point[] points, Color color) {
		if (target !is null) {
			Graphics.drawFilledPolygon(target, color, points);
		}
	}

	void drawSurface(Surface src, int x, int y, bool useAlpha = true, ubyte globalAlpha = 255) {
		if (target !is null && src !is null) {
			target.blit(src, x, y, useAlpha, globalAlpha);
		}
	}

	void drawSurfaceRotated(Surface src, int x, int y, float angleRadians) {
		if (target !is null && src !is null) {
			blitRotated(target, src, x, y, angleRadians);
		}
	}

	void drawSurfaceScaled(Surface src, Rect destRect) {
		if (target !is null && src !is null) {
			auto scaled = scaleSurface(src, destRect.w, destRect.h);
			target.blit(scaled, destRect.x, destRect.y);
		}
	}

	void drawTexture(ITexture texture, Rect srcRect, Rect destRect, Color tint = Colors.white) {
		// Fallback for software texture
	}
}

/// Graphics drawing functions
struct Graphics {
	static void drawPolygon(ref Surface surface, Color color, Point[] points, int thickness = 1) {
		if (points.length < 2)
			return;

		foreach (i; 0 .. points.length) {
			drawLine(
				surface,
				color,
				points[i],
				points[(i + 1) % points.length],
				thickness
			);
		}
	}

	static void drawFilledPolygon(ref Surface surface, Color color, Point[] points) {
		if (points.length < 3)
			return;

		int minY = points[0].y;
		int maxY = points[0].y;

		foreach (p; points) {
			if (p.y < minY) minY = p.y;
			if (p.y > maxY) maxY = p.y;
		}

		minY = max(minY, 0);
		maxY = min(maxY, cast(int)surface.height - 1);

		int[] nodes;
		nodes.reserve(points.length);

		for (int y = minY; y <= maxY; y++) {
			nodes.length = 0;

			foreach (i; 0 .. points.length) {
				Point p1 = points[i];
				Point p2 = points[(i + 1) % points.length];

				if (p1.y == p2.y)
					continue;

				if ((p1.y < y && p2.y >= y) ||
					(p2.y < y && p1.y >= y))
				{
					int x = p1.x +
						cast(int)((cast(float)(y - p1.y) *
						cast(float)(p2.x - p1.x)) /
						cast(float)(p2.y - p1.y));

					nodes ~= x;
				}
			}

			sort(nodes);

			foreach (i; 0 .. nodes.length / 2) {
				int x0 = nodes[i * 2];
				int x1 = nodes[i * 2 + 1];

				if (x0 > x1)
					swap(x0, x1);

				x0 = max(x0, 0);
				x1 = min(x1, cast(int)surface.width - 1);

				if (surface.useClip) {
					if (y < surface.clipRect.y ||
						y >= surface.clipRect.y + surface.clipRect.h)
						continue;

					x0 = max(x0, surface.clipRect.x);
					x1 = min(x1, surface.clipRect.x + surface.clipRect.w - 1);
				}

				if (x0 > x1)
					continue;

				size_t index = cast(size_t)y * surface.width + cast(size_t)x0;

				if (color.a == 255) {
					for (int x = x0; x <= x1; x++) {
						surface.data[index++] = color;
					}
				} else if (color.a > 0) {
					for (int x = x0; x <= x1; x++) {
						surface.data[index] = alphaBlend(color, surface.data[index]);
						index++;
					}
				}
			}
		}
	}

	static void drawLine(ref Surface surface, Color color, Point p0, Point p1, int thickness = 1) {
		int dx = p1.x - p0.x;
		int dy = p1.y - p0.y;

		if (isNaN(cast(float)dx) || isNaN(cast(float)dy)) return;

		int steps = abs(dx) > abs(dy) ? abs(dx) : abs(dy);
		
		if (steps > 10000) steps = 10000; 

		auto drawThicknessPoint = (float fx, float fy) {
			if (isNaN(fx) || isNaN(fy)) return;
			int ix = cast(int)fx;
			int iy = cast(int)fy;
			
			if (thickness <= 1) {
				if (ix >= 0 && iy >= 0 && ix < cast(int)surface.width && iy < cast(int)surface.height) {
					surface.data[cast(size_t)iy * surface.width + cast(size_t)ix] = color;
				}
			} else {
				int offset = thickness / 2;
				for (int ty = 0; ty < thickness; ty++) {
					for (int tx = 0; tx < thickness; tx++) {
						int nx = ix + tx - offset;
						int ny = iy + ty - offset;
						if (nx >= 0 && ny >= 0 && nx < cast(int)surface.width && ny < cast(int)surface.height) {
							surface.data[cast(size_t)ny * surface.width + cast(size_t)nx] = color;
						}
					}
				}
			}
		};

		if (steps == 0) {
			drawThicknessPoint(cast(float)p0.x, cast(float)p0.y);
			return;
		}

		float xInc = dx / (cast(float)steps);
		float yInc = dy / (cast(float)steps);
		
		float x = cast(float)p0.x;
		float y = cast(float)p0.y;
		for (int i = 0; i <= steps; i++) {
			drawThicknessPoint(x, y);
			x += xInc;
			y += yInc;
		}
	}

	static void drawDottedLine(ref Surface surface, Color color, Point p0, Point p1, int dotLen = 5, int gapLen = 5, int thickness = 1) {
		int dx = p1.x - p0.x;
		int dy = p1.y - p0.y;
		int steps = cast(int)(sqrt(cast(float)dx*dx + cast(float)dy*dy));
		
		if (steps > 10000) steps = 10000;
		if (steps == 0) return;

		float xInc = dx / cast(float)steps;
		float yInc = dy / cast(float)steps;
		
		float x = cast(float)p0.x;
		float y = cast(float)p0.y;
		
		int patternLen = dotLen + gapLen;
		
		for (int i = 0; i <= steps; i++) {
			if ((i % patternLen) < dotLen) {
				int ix = cast(int)x;
				int iy = cast(int)y;
				
				if (thickness <= 1) {
					if (ix >= 0 && iy >= 0 && ix < cast(int)surface.width && iy < cast(int)surface.height) {
						surface.data[cast(size_t)iy * surface.width + cast(size_t)ix] = color;
					}
				} else {
					int offset = thickness / 2;
					for (int ty = 0; ty < thickness; ty++) {
						for (int tx = 0; tx < thickness; tx++) {
							int nx = ix + tx - offset;
							int ny = iy + ty - offset;
							if (nx >= 0 && ny >= 0 && nx < cast(int)surface.width && ny < cast(int)surface.height) {
								surface.data[cast(size_t)ny * surface.width + cast(size_t)nx] = color;
							}
						}
					}
				}
			}
			x += xInc;
			y += yInc;
		}
	}
	static void drawRect(ref Surface surface, Color color, Rect rect) {
		int x0 = max(0, rect.x);
		int y0 = max(0, rect.y);
		int x1 = min(cast(int)surface.width, rect.x + rect.w);
		int y1 = min(cast(int)surface.height, rect.y + rect.h);

		if (surface.useClip) {
			x0 = max(x0, surface.clipRect.x);
			y0 = max(y0, surface.clipRect.y);
			x1 = min(x1, surface.clipRect.x + surface.clipRect.w);
			y1 = min(y1, surface.clipRect.y + surface.clipRect.h);
		}

		if (x0 >= x1 || y0 >= y1) return;

		if (color.a == 255) {
			for (int y = y0; y < y1; y++) {
				Color* line = &surface.data[y * surface.width + x0];
				int width = x1 - x0;
				line[0 .. width] = color;
			}
		} else if (color.a > 0) {
			uint a  = color.a;
			uint ia = 255 - a;
			uint sr = color.r * a;
			uint sg = color.g * a;
			uint sb = color.b * a;

			// Per-channel LUT: precomputed blend for all 256 possible dst values.
			// 768 bytes total — fits entirely in L1 cache.
			// Replaces 3 multiplications + 3 shifts per pixel with 3 table lookups.
			ubyte[256] rLUT = void, gLUT = void, bLUT = void;
			foreach (i; 0 .. 256) {
				rLUT[i] = cast(ubyte)((sr + i * ia) * 257 >> 16);
				gLUT[i] = cast(ubyte)((sg + i * ia) * 257 >> 16);
				bLUT[i] = cast(ubyte)((sb + i * ia) * 257 >> 16);
			}

			for (int y = y0; y < y1; y++) {
				Color* line = &surface.data[y * surface.width + x0];
				int width   = x1 - x0;
				for (int x = 0; x < width; x++) {
					Color d = line[x];
					line[x] = Color(rLUT[d.r], gLUT[d.g], bLUT[d.b], 255);
				}
			}
		}
	}

	static void drawRectOutline(ref Surface surface, Color color, Rect rect, uint thickness = 1) {
		if (rect.w <= 0 || rect.h <= 0)
			return;

		int x0 = rect.x;
		int y0 = rect.y;
		int x1 = rect.x + rect.w - 1;
		int y1 = rect.y + rect.h - 1;

		for (uint i = 0; i < thickness; i++) {
			int left   = x0 + cast(int)i;
			int right  = x1 - cast(int)i;
			int top    = y0 + cast(int)i;
			int bottom = y1 - cast(int)i;

			if (left > right || top > bottom)
				break;

			for (int x = left; x <= right; x++) {
				if (top >= 0 && top < surface.height &&
					x >= 0 && x < surface.width)
					surface.data[top * surface.width + x] = color;
			}

			for (int x = left; x <= right; x++) {
				if (bottom >= 0 && bottom < surface.height &&
					x >= 0 && x < surface.width)
					surface.data[bottom * surface.width + x] = color;
			}

			for (int y = top; y <= bottom; y++) {
				if (y >= 0 && y < surface.height &&
					left >= 0 && left < surface.width)
					surface.data[y * surface.width + left] = color;
			}

			for (int y = top; y <= bottom; y++) {
				if (y >= 0 && y < surface.height &&
					right >= 0 && right < surface.width)
					surface.data[y * surface.width + right] = color;
			}
		}
	}

	static void drawCircle(ref Surface surface, Color color, Point center, int radius) {
		if (radius <= 0) return;
		int x = radius;
		int y = 0;
		int err = 0;

		auto setP = (int px, int py) {
			if (px >= 0 && py >= 0 && px < cast(int)surface.width && py < cast(int)surface.height) {
				surface.data[cast(size_t)py * surface.width + cast(size_t)px] = color;
			}
		};

		while (x >= y) {
			setP(center.x + x, center.y + y);
			setP(center.x + y, center.y + x);
			setP(center.x - y, center.y + x);
			setP(center.x - x, center.y + y);
			setP(center.x - x, center.y - y);
			setP(center.x - y, center.y - x);
			setP(center.x + y, center.y - x);
			setP(center.x + x, center.y - y);

			if (err <= 0) {
				y += 1;
				err += 2 * y + 1;
			}
			if (err > 0) {
				x -= 1;
				err -= 2 * x + 1;
			}
		}
	}

	static void drawFilledCircle(ref Surface surface, Color color, Point center, int radius) {
		if (radius <= 0) return;
		for (int dy = -radius; dy <= radius; dy++) {
			int dxLimit = cast(int)sqrt(cast(float)(radius * radius - dy * dy));
			int y = center.y + dy;
			if (y < 0 || y >= cast(int)surface.height) continue;

			int xStart = max(0, center.x - dxLimit);
			int xEnd = min(cast(int)surface.width - 1, center.x + dxLimit);

			size_t baseIndex = cast(size_t)y * surface.width;
			for (int x = xStart; x <= xEnd; x++) {
				surface.data[baseIndex + cast(size_t)x] = color;
			}
		}
	}
}

Surface getTestSurface(uint width, uint height, Color color1 = Color(127,127,127), Color color2=Color(255,255,255)) {
	Surface testSurface = new Surface(width, height);
	testSurface.fill(color2);
	Graphics.drawRect(testSurface, color1, Rect(0,0, width/2, height/2));
	Graphics.drawRect(testSurface, color1, Rect(width/2,height/2, width/2, height/2));
	return testSurface;
}

Surface getErrorSurface(uint width, uint height, Color color1 = Color(255,0,127), Color color2=Color(255,255,255)) {
	return getTestSurface(width, height, color1, color2);
}

static Color alphaBlendFast(Color src, Color dst) {
	uint a  = src.a;
	uint ia = 255 - a;

	ubyte r = cast(ubyte)((src.r * a + dst.r * ia) / 255);
	ubyte g = cast(ubyte)((src.g * a + dst.g * ia) / 255);
	ubyte b = cast(ubyte)((src.b * a + dst.b * ia) / 255);

	return Color(r, g, b, 255);
}

static Color alphaBlend(Color src, Color dst) {
	if (src.a == 255) return src;
	if (src.a == 0) return dst;

	uint a = src.a;
	uint ia = 255 - a;

	// Fast approximation: (x * 257) >> 16 ≈ x / 255, avoids integer division
	return Color(
		cast(ubyte)((src.r * a + dst.r * ia) * 257 >> 16),
		cast(ubyte)((src.g * a + dst.g * ia) * 257 >> 16),
		cast(ubyte)((src.b * a + dst.b * ia) * 257 >> 16),
		cast(ubyte)(src.a + ((dst.a * ia) * 257 >> 16))
	);
}

/++
Generate PPM3 format file from Surface
Format: RGB
+/
string exportPPM3(Surface surface){
	string content="P3\n";
	content ~=format("%d %d\n", surface.width, surface.height);
	content ~="255\n";

	foreach (pixel; surface.data) {
		content ~= format("%d %d %d ", pixel.r, pixel.g, pixel.b);
	}
	content ~= "\n";
	return content;
}

/++
Load Surface content from PPM3 file
Format: RGB
+/
void loadPPM3(Surface* surface, string path)
{
	import std.file : readText;
	import std.array : split;
	import std.conv : to;
	
	auto txt = readText(path);
	auto tokens = txt.split();

	size_t i = 0;

	assert(tokens[i] == "P3");
	i++;

	uint w = tokens[i++].to!uint;
	uint h = tokens[i++].to!uint;

	uint maxv = tokens[i++].to!uint;
	assert(maxv == 255);

	surface.resize(w, h);

	foreach (y; 0 .. h)
	foreach (x; 0 .. w)
	{
		uint r = tokens[i++].to!uint;
		uint g = tokens[i++].to!uint;
		uint b = tokens[i++].to!uint;

		surface.setPixel(Point(x,y), Color(r,g,b,255));
	}
}

Surface scaleSurface(Surface src, int newW, int newH)
{
	if (newW <= 0 || newH <= 0 || src is null || src.width <= 0 || src.height <= 0) {
		return new Surface(max(1, newW), max(1, newH));
	}

	if (newW == cast(int)src.width && newH == cast(int)src.height) {
		return src.dup;
	}

	auto dst = new Surface(newW, newH);

	Color* dstData = dst.rawData.ptr;
	const(Color)* srcData = src.rawData.ptr;

	int srcW = cast(int)src.width;
	int srcH = cast(int)src.height;

	float sx = (newW > 1) ? cast(float)(srcW - 1) / (newW - 1) : 0.0f;
	float sy = (newH > 1) ? cast(float)(srcH - 1) / (newH - 1) : 0.0f;

	for (int y = 0; y < newH; y++)
	{
		float srcY = y * sy;
		int y0 = cast(int)srcY;
		int y1 = min(y0 + 1, srcH - 1);
		float dy = srcY - y0;
		float invDy = 1.0f - dy;

		size_t dstRowOffset = y * newW;
		size_t srcRow0Offset = y0 * srcW;
		size_t srcRow1Offset = y1 * srcW;

		for (int x = 0; x < newW; x++)
		{
			float srcX = x * sx;
			int x0 = cast(int)srcX;
			int x1 = min(x0 + 1, srcW - 1);
			float dx = srcX - x0;
			float invDx = 1.0f - dx;

			float w00 = invDx * invDy;
			float w10 = dx * invDy;
			float w01 = invDx * dy;
			float w11 = dx * dy;

			Color c00 = srcData[srcRow0Offset + x0];
			Color c10 = srcData[srcRow0Offset + x1];
			Color c01 = srcData[srcRow1Offset + x0];
			Color c11 = srcData[srcRow1Offset + x1];

			uint r = cast(uint)(c00.r*w00 + c10.r*w10 + c01.r*w01 + c11.r*w11);
			uint g = cast(uint)(c00.g*w00 + c10.g*w10 + c01.g*w01 + c11.g*w11);
			uint b = cast(uint)(c00.b*w00 + c10.b*w10 + c01.b*w01 + c11.b*w11);
			uint a = cast(uint)(c00.a*w00 + c10.a*w10 + c01.a*w01 + c11.a*w11);

			dstData[dstRowOffset + x] = Color(r, g, b, a);
		}
	}

	return dst;
}

Outcome!Surface surfaceFromImage(string filePath)
{
	import arsd.image;

	auto img = loadImageFromFile(filePath);

	if (img is null)
		return Outcome!Surface(Result.unknown_error, "Failed to load image file.");

	auto surface = new Surface(img.width, img.height);

	foreach (y; 0 .. img.height)
	{
		foreach (x; 0 .. img.width)
		{
			auto c = img.getPixel(x, y);

			surface.setPixel(
				zame.core.common.Point(x, y),
				zame.core.common.Color(c.r, c.g, c.b, c.a)
			);
		}
	}

	return Outcome!Surface(surface);
}

ResultStatus loadFromPng(ref Surface dest, string filePath)
{
	auto res = surfaceFromImage(filePath);
	if (res.ok) {
		dest.resize(res.value.width, res.value.height);
		dest.blit(res.value, 0, 0, false);
	}
	return res.status;
}

Surface rotateSurface(Surface src, float angleRadians) {
	float cosA = cos(angleRadians);
	float sinA = sin(angleRadians);

	int w = cast(int)src.width;
	int h = cast(int)src.height;

	float x1 = -w/2.0f * cosA - (-h/2.0f) * sinA;
	float y1 = -w/2.0f * sinA + (-h/2.0f) * cosA;
	float x2 = w/2.0f * cosA - (-h/2.0f) * sinA;
	float y2 = w/2.0f * sinA + (-h/2.0f) * cosA;
	float x3 = w/2.0f * cosA - h/2.0f * sinA;
	float y3 = w/2.0f * sinA + h/2.0f * cosA;
	float x4 = -w/2.0f * cosA - h/2.0f * sinA;
	float y4 = -w/2.0f * sinA + h/2.0f * cosA;

	import std.algorithm : min, max;
	float minX = min(min(x1, x2), min(x3, x4));
	float maxX = max(max(x1, x2), max(x3, x4));
	float minY = min(min(y1, y2), min(y3, y4));
	float maxY = max(max(y1, y2), max(y3, y4));

	int newW = cast(int)(maxX - minX) + 1;
	int newH = cast(int)(maxY - minY) + 1;

	auto dst = new Surface(newW, newH);
	dst.fill(Colors.transparent);

	float centerX = newW / 2.0f;
	float centerY = newH / 2.0f;
	float srcCenterX = w / 2.0f;
	float srcCenterY = h / 2.0f;

	for (int y = 0; y < newH; y++) {
		for (int x = 0; x < newW; x++) {
			float dx = x - centerX;
			float dy = y - centerY;

			float srcX = dx * cosA + dy * sinA + srcCenterX;
			float srcY = -dx * sinA + dy * cosA + srcCenterY;

			int sx = cast(int)(srcX);
			int sy = cast(int)(srcY);

			if (sx >= 0 && sx < w && sy >= 0 && sy < h) {
				dst.data[cast(size_t)y * cast(size_t)newW + cast(size_t)x] = src.data[cast(size_t)sy * cast(size_t)src.width + cast(size_t)sx];
			}
		}
	}

	return dst;
}

void blitRotated(Surface dest, Surface src, int destX, int destY, float angleRadians) {
	float cosA = cos(angleRadians);
	float sinA = sin(angleRadians);
	
	float hw = src.width / 2.0f;
	float hh = src.height / 2.0f;
	
	float x1 = -hw * cosA - (-hh) * sinA;
	float y1 = -hw * sinA + (-hh) * cosA;
	float x2 = hw * cosA - (-hh) * sinA;
	float y2 = hw * sinA + (-hh) * cosA;
	float x3 = hw * cosA - hh * sinA;
	float y3 = hw * sinA + hh * cosA;
	float x4 = -hw * cosA - hh * sinA;
	float y4 = -hw * sinA + hh * cosA;
	
	import std.algorithm : min, max;
	int minX = cast(int)(min(min(x1, x2), min(x3, x4)));
	int maxX = cast(int)(max(max(x1, x2), max(x3, x4))) + 1;
	int minY = cast(int)(min(min(y1, y2), min(y3, y4)));
	int maxY = cast(int)(max(max(y1, y2), max(y3, y4))) + 1;
	
	int startX = max(0, destX + minX);
	int endX = min(cast(int)dest.width, destX + maxX);
	int startY = max(0, destY + minY);
	int endY = min(cast(int)dest.height, destY + maxY);
	
	if (dest.useClip) {
		startX = max(startX, dest.clipRect.x);
		endX = min(endX, dest.clipRect.x + dest.clipRect.w);
		startY = max(startY, dest.clipRect.y);
		endY = min(endY, dest.clipRect.y + dest.clipRect.h);
	}
	
	if (startX >= endX || startY >= endY) return;
	
	for (int y = startY; y < endY; y++) {
		float relY = y - destY;
		for (int x = startX; x < endX; x++) {
			float relX = x - destX;
			
			// Inverse transform to find source pixel
			float srcX = relX * cosA + relY * sinA + hw;
			float srcY = -relX * sinA + relY * cosA + hh;
			
			int sx = cast(int)srcX;
			int sy = cast(int)srcY;
			
			if (sx >= 0 && sx < cast(int)src.width && sy >= 0 && sy < cast(int)src.height) {
				Color sc = src.data[cast(size_t)sy * cast(size_t)src.width + cast(size_t)sx];
				if (sc.a == 0) continue;
				size_t destIndex = cast(size_t)y * dest.width + cast(size_t)x;
				if (sc.a == 255) {
					dest.data[destIndex] = sc;
				} else {
					dest.data[destIndex] = alphaBlend(sc, dest.data[destIndex]);
				}
			}
		}
	}
}

Point blitCentered(Surface surface, Surface destSurface, int x, int y) {
	int posX = x;
	int posY = y;
	if (x == -1) posX=destSurface.width/2-surface.width/2;
	if (y == -1) posY=destSurface.height/2-surface.height/2;

	destSurface.blit(surface, posX, posY);
	return Point(posX, posY);
}

Surface rotate3DY(Surface surface, float angleDegrees, float distance, float scale, Color bgColor = Color(0, 0, 0, 0)) {
	import std.algorithm.comparison : max;

	float maxScale = max(1.0f, scale);
	int outWidth  = cast(int)ceil(surface.width  * maxScale * 1.5f);
	int outHeight = cast(int)ceil(surface.height * maxScale * 1.5f);

	Surface outSurface = new Surface(outWidth, outHeight);
	outSurface.fill(bgColor);

	float rad   = angleDegrees * PI / 180.0f;
	float cosA  = cos(rad);
	float sinA  = sin(rad);

	float focalLength = distance * scale;
	float destCenterX = outSurface.width  / 2.0f;
	float destCenterY = outSurface.height / 2.0f;
	float srcCenterX  = surface.width  / 2.0f;
	float srcCenterY  = surface.height / 2.0f;

	for (int dy = 0; dy < outSurface.height; dy++) {
		for (int dx = 0; dx < outSurface.width; dx++) {
			float screenX = dx - destCenterX + 0.5f;
			float screenY = dy - destCenterY + 0.5f;

			float denom = focalLength * cosA - screenX * sinA;

			if (abs(denom) < 0.001f)  continue;
			if (denom * cosA <= 0.0f) continue;

			float sx = (screenX * distance) / denom;
			float sy = (screenY * distance * cosA) / denom;

			int srcX = cast(int)floor(sx + srcCenterX);
			int srcY = cast(int)floor(sy + srcCenterY);

			Point srcPoint = Point(srcX, srcY);
			if (surface.isValidPoint(srcPoint)) {
				outSurface.setPixel(Point(dx, dy), surface.getPixel(srcPoint));
			}
		}
	}
	return outSurface;
}
