module zame.core.graphics;

import std.math;
import std.conv;
import std.range;
import std.format;
import std.algorithm;
import zame.core.common;
import std.stdio;

enum Colors: Color {
	transparent = Color(255,255,255,0),
	black = Color(0, 0, 0),
	white = Color(255, 255, 255),
	red = Color(255, 0 , 0),
	green = Color(0, 255, 0),
	blue = Color(0, 0, 255),
	yellow = Color(255, 255, 0),
	orange = Color(255, 165, 0),
	purple = Color(128, 0, 128)
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

	void resize(uint width, uint height) {
		this.width = width;
		this.height = height;
		this.data = new Color[this.width*this.height];
	}

	void fill(Color fillColor) {
		foreach (i; 0 .. data.length) {
			data[i] = fillColor;
		}
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

	void setClip(Rect rect) {
		clipRect = rect;
		useClip = true;
	}

	void resetClip() {
		useClip = false;
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
					srcX < this.width && srcY < this.height)
				{
					color = this.getPixel(Point(srcX, srcY));
				}
				else
				{
					color = fallBackColor;
				}

				outSurface.setPixel(Point(x, y), color);
			}
		}

		return outSurface;
	}


	void blit(Surface src, int destX, int destY, bool useAlpha = true, ubyte globalAlpha = 255) {
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

		for (int y = 0; y < blitHeight; y++) {
			int sy = srcStartY + y;
			int dy = destY + y;
			
			// Bounds check to prevent overflow in both source and destination
			if (sy < 0 || sy >= cast(int)src.height) continue;
			if (dy < 0 || dy >= cast(int)height) continue;
			
			// Additional check to ensure the calculated index won't overflow
			size_t srcIndex = sy * src.width + srcStartX;
			size_t dstIndex = dy * this.width + destX;
			if (srcIndex >= src.rawData.length || dstIndex >= data.length) continue;
			
			Color* srcLine = &src.data[srcIndex];
			Color* dstLine = &data[dstIndex];

			if (!useAlpha && globalAlpha == 255) {
				import core.stdc.string : memcpy;
				memcpy(dstLine, srcLine, blitWidth * Color.sizeof);
			} else {
				for (int x = 0; x < blitWidth; x++) {
					Color sc = srcLine[x];
                    if (globalAlpha != 255) {
                        sc.a = cast(ubyte)(sc.a * globalAlpha / 255);
                    }

					if (sc.a == 0) continue;
					if (sc.a == 255) {
						dstLine[x] = sc;
					} else {
						dstLine[x] = alphaBlend(sc, dstLine[x]);
					}
				}
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

	override string toString() {
		return "Surface<"~this.width.to!string~"x"~this.height.to!string~">";
	} 

	Surface flip(bool horizontal, bool vertical) {
		Surface outSurface = new Surface(this.width, this.height);
		for (int y = 0; y < cast(int)this.height; y++) {
			for (int x = 0; x < cast(int)this.width; x++) {
				int srcX = horizontal ? (cast(int)this.width - 1 - x) : x;
				int srcY = vertical ? (cast(int)this.height - 1 - y) : y;
				outSurface.setPixel(Point(x, y), this.getPixel(Point(srcX, srcY)));
			}
		}
		return outSurface;
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
class Animation {
	Surface[] frames;
	size_t currentFrame;
	Timer timer;

	this(Surface[] frames, Timer timer) {
		this.frames = frames;
		this.timer = timer;
	}

	void update(float dt) {
		if (timer.tick()) {
			currentFrame = (currentFrame + 1) % frames.length;
		}
	}

	void reset() {
		timer.reset();
		currentFrame = 0;
	}

	Surface getCurrentFrame() {
		return frames[currentFrame];
	}

	Surface getFrame(size_t index) {
		return frames[index];
	}
}

class AnimationManager {
	Animation[string] animations;
	Animation currentAnim;
	string currentAnimName;

	this(Animation[string] animations) {
		this.animations = animations;
	}

	Outcome!bool setCurrentAnimation(string id) {
		if (auto p = id in animations) {
			currentAnim = *p;
			currentAnimName = id;
			return success(true);
		}
		
		return failure!bool(Result.animation_not_exists, "Animation '" ~ id ~ "' does not exist");
	}

	void reset() {
		foreach(Animation animation; animations) {
			animation.reset();
		}
	}

	void update(float dt) {
		if (currentAnim is null) return;

		currentAnim.update(dt);
	}

	Surface getCurrentFrame() {
		if (currentAnim is null) return getErrorSurface(32,32);

		return currentAnim.getCurrentFrame();
	}
}

struct Graphics {
	static void drawLine(ref Surface surface, Color color, Point p0, Point p1, int thickness = 1) {
		int dx = p1.x - p0.x;
		int dy = p1.y - p0.y;

        import std.math : isNaN;
        if (isNaN(cast(float)dx) || isNaN(cast(float)dy)) return;

		int steps = abs(dx) > abs(dy) ? abs(dx) : abs(dy);
        
        // Safety check to prevent infinite loops from garbage values
        if (steps > 10000) steps = 10000; 

		auto drawThicknessPoint = (float fx, float fy) {
            if (isNaN(fx) || isNaN(fy)) return;
			int ix = fx.to!int;
			int iy = fy.to!int;
			
			if (thickness <= 1) {
				if (ix >= 0 && iy >= 0 && ix < surface.width && iy < surface.height) {
					surface.setPixel(Point(ix, iy), color);
				}
			} else {
				int offset = thickness / 2;
				for (int ty = 0; ty < thickness; ty++) {
					for (int tx = 0; tx < thickness; tx++) {
						int nx = ix + tx - offset;
						int ny = iy + ty - offset;
						if (nx >= 0 && ny >= 0 && nx < surface.width && ny < surface.height) {
							surface.setPixel(Point(nx, ny), color);
			}
					}
				}
			}
		};

		if (steps == 0) {
			drawThicknessPoint(p0.x.to!float, p0.y.to!float);
			return;
		}

		float xInc = dx / steps.to!float;
		float yInc = dy / steps.to!float;
		
		float x = p0.x.to!float;
		float y = p0.y.to!float;
		for (int i = 0; i <= steps; i++) {
			drawThicknessPoint(x, y);
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
				for (int x = 0; x < width; x++) {
					line[x] = color;
				}
			}
		} else if (color.a > 0) {
			for (int y = y0; y < y1; y++) {
				Color* line = &surface.data[y * surface.width + x0];
				int width = x1 - x0;
				for (int x = 0; x < width; x++) {
					line[x] = alphaBlend(color, line[x]);
				}
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

    // More accurate integer alpha blending: (src * a + dst * (255 - a)) / 255
    ubyte r = cast(ubyte)((src.r * a + dst.r * ia) / 255);
    ubyte g = cast(ubyte)((src.g * a + dst.g * ia) / 255);
    ubyte b = cast(ubyte)((src.b * a + dst.b * ia) / 255);
    
    // Alpha composite: src.a + dst.a * (255 - src.a) / 255
    ubyte outA = cast(ubyte)(src.a + ((dst.a * ia) / 255));

    return Color(r, g, b, outA);
}

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
	if (newW <= 0 || newH <= 0 || src.width <= 0 || src.height <= 0) {
        return new Surface(max(1, newW), max(1, newH));
    }

	auto dst = new Surface(newW, newH);

	float sx = (newW > 1) ? cast(float)(src.width - 1) / (newW - 1) : 0.0f;
	float sy = (newH > 1) ? cast(float)(src.height - 1) / (newH - 1) : 0.0f;

	for (int y = 0; y < newH; y++)
	{
		float srcY = y * sy;
		int y0 = cast(int)srcY;
		int y1 = min(y0 + 1, src.height - 1);
		float dy = srcY - y0;

		for (int x = 0; x < newW; x++)
		{
			float srcX = x * sx;
			int x0 = cast(int)srcX;
			int x1 = min(x0 + 1, src.width - 1);
			float dx = srcX - x0;

			Color c00 = src.rawData[y0 * src.width + x0];
			Color c10 = src.rawData[y0 * src.width + x1];
			Color c01 = src.rawData[y1 * src.width + x0];
			Color c11 = src.rawData[y1 * src.width + x1];

			uint r = cast(uint)(c00.r*(1-dx)*(1-dy) + c10.r*dx*(1-dy) + c01.r*(1-dx)*dy + c11.r*dx*dy);
			uint g = cast(uint)(c00.g*(1-dx)*(1-dy) + c10.g*dx*(1-dy) + c01.g*(1-dx)*dy + c11.g*dx*dy);
			uint b = cast(uint)(c00.b*(1-dx)*(1-dy) + c10.b*dx*(1-dy) + c01.b*(1-dx)*dy + c11.b*dx*dy);
			uint a = cast(uint)(c00.a*(1-dx)*(1-dy) + c10.a*dx*(1-dy) + c01.a*(1-dx)*dy + c11.a*dx*dy);

			dst.rawData[y * newW + x] = Color(r, g, b, a);
		}
	}

	return dst;
}

Outcome!Surface surfaceFromImage(string filePath)
{
	import gamut;

	Image img;
	img.loadFromFile(
		filePath,
		LOAD_RGB | LOAD_ALPHA | LOAD_8BIT | LOAD_NO_PREMUL
	);

	if (img.isError)
		return Outcome!Surface(Result.unknown_error, img.errorMessage.idup);

	if (img.type != PixelType.rgba8)
		return Outcome!Surface(Result.unknown, "Image is not RGBA8");

	auto surface = new Surface(img.width, img.height);

	foreach (y; 0 .. img.height)
	{
		ubyte* scan = cast(ubyte*) img.scanptr(y);
		foreach (x; 0 .. img.width)
		{
			uint r = scan[x * 4 + 0];
			uint g = scan[x * 4 + 1];
			uint b = scan[x * 4 + 2];
			uint a = scan[x * 4 + 3];

			surface.setPixel(Point(x, y), Color(r, g, b, a));
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
	import std.math : sin, cos, abs, PI;
	
	// Calculate bounding box for rotated image
	float cosA = cos(angleRadians);
	float sinA = sin(angleRadians);
	
	int w = src.width;
	int h = src.height;
	
	// Calculate corners of rotated rectangle
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
	
	// Reverse rotation matrix
	float centerX = newW / 2.0f;
	float centerY = newH / 2.0f;
	float srcCenterX = w / 2.0f;
	float srcCenterY = h / 2.0f;
	
	for (int y = 0; y < newH; y++) {
		for (int x = 0; x < newW; x++) {
			// Translate to origin
			float dx = x - centerX;
			float dy = y - centerY;
			
			// Rotate backwards
			float srcX = dx * cosA + dy * sinA + srcCenterX;
			float srcY = -dx * sinA + dy * cosA + srcCenterY;
			
			// Sample from source
			int sx = cast(int)(srcX);
			int sy = cast(int)(srcY);
			
			if (sx >= 0 && sx < w && sy >= 0 && sy < h) {
				dst.setPixel(Point(x, y), src.getPixel(Point(sx, sy)));
			}
		}
	}
	
	return dst;
}

void blitRotated(Surface dest, Surface src, int destX, int destY, float angleRadians) {
	Surface rotated = rotateSurface(src, angleRadians);
	dest.blit(rotated, destX - rotated.width/2, destY - rotated.height/2);
}

void blitCentered(ref Surface surface, ref Surface destSurface, int x, int y) {
	int posX = x;
	int posY = y;
	if (x == -1) posX=destSurface.width/2-surface.width/2;
	if (y == -1) posY=destSurface.height/2-surface.height/2;

	destSurface.blit(surface, posX, posY);
}
