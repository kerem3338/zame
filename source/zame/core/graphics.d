module zame.core.graphics;

import std.math;
import std.conv;
import std.range;
import std.format;
import std.algorithm;
import zame.core.common;

enum Colors: Color {
	transparent = Color(255,255,255,0),
	black = Color(0, 0, 0),
	white = Color(255, 255, 255),
	red = Color(255, 0 , 0),
	green = Color(0, 255, 0),
	blue = Color(0, 0, 255)
}

class Surface {
	uint width;
	uint height;
	private Color[] data;

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

	void blit(Surface src, Point where) {
		blit(src, where.x, where.y);
	}

	Surface subSurface(Rect rect, Color fallBackColor = Colors.transparent) {
		Surface outSurface = new Surface(rect.size.w, rect.size.h);

		for (int y = 0; y < rect.size.h; y++) {
			for (int x = 0; x < rect.size.w; x++) {

				int srcX = rect.loc.x + x;
				int srcY = rect.loc.y + y;

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


	void blit(Surface src, int destX, int destY, bool useAlpha = true) {
		foreach (y; 0 .. src.height) {
			int dstY = destY + y;
			if (dstY < 0 || dstY >= cast(int)height) continue;

			foreach (x; 0 .. src.width) {
				int dstX = destX + x;
				if (dstX < 0 || dstX >= cast(int)width) continue;

				Color srcColor = src.data[y * src.width + x];
				if (useAlpha) {
					if (srcColor.a == 0) continue;
					if (srcColor.a == 255) {
						this.data[dstY * width + dstX] = srcColor;
					} else {
						Color dstColor = this.data[dstY * width + dstX];
						this.data[dstY * width + dstX] = alphaBlend(srcColor, dstColor);
					}
				} else {
					this.data[dstY * width + dstX] = srcColor;
				}
			}
		}
	}

	override string toString() {
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
class Animation {
	Surface[] frames;
	size_t currentFrame;
	Timer timer;

	this(Surface[] frames, Timer timer) {
		this.frames = frames;
		this.timer = timer;
	}

	void update() {
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

	this(Animation[string] animations) {
		this.animations = animations;
	}

	Outcome!bool setCurrentAnimation(string id) {
		if (auto p = id in animations) {
			currentAnim = *p;
			return success(true);
		}
		
		return failure!bool(Result.animation_not_exists, "Animation '" ~ id ~ "' does not exist");
	}

	void reset() {
		foreach(Animation animation; animations) {
			animation.reset();
		}
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

		int steps = abs(dx) > abs(dy) ? abs(dx) : abs(dy);

		auto drawThicknessPoint = (float fx, float fy) {
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

		int x0 = rect.loc.x;
		int y0 = rect.loc.y;
		int x1 = rect.loc.x + rect.size.w;
		int y1 = rect.loc.y + rect.size.h;

		foreach (y; y0 .. y1) {
			foreach (x; x0 .. x1) {

				if (x < 0 || y < 0 ||
					x >= surface.width ||
					y >= surface.height)
					continue;

				Color dst = surface.getPixel(Point(x, y));

				surface.setPixel(
					Point(x, y),
					alphaBlend(color, dst)
				);
			}
		}
	}
}

Surface getTestSurface(uint width, uint height, Color color1 = Color(127,127,127), Color color2=Color(255,255,255)) {
	Surface testSurface = new Surface(width, height);
	testSurface.fill(color2);
	Graphics.drawRect(testSurface, color1, Rect(Point(0,0), Size(width/2, height/2)));
	Graphics.drawRect(testSurface, color1, Rect(Point(width/2,height/2), Size(width/2, height/2)));
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

Color alphaBlend(Color src, Color dst) {
	if (src.a == 255) return src;
	if (src.a == 0)   return dst;

	float a = src.a / 255.0f;
	float ia = 1.0f - a;

	ubyte r = cast(ubyte)(src.r * a + dst.r * ia);
	ubyte g = cast(ubyte)(src.g * a + dst.g * ia);
	ubyte b = cast(ubyte)(src.b * a + dst.b * ia);
	
	// Composite alpha
	ubyte outA = cast(ubyte)(src.a + (dst.a * (255 - src.a) / 255));

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
	auto dst = new Surface(newW, newH);

	float sx = cast(float)(src.width - 1) / (newW - 1);
	float sy = cast(float)(src.height - 1) / (newH - 1);

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

void blitCentered(ref Surface surface, ref Surface destSurface, int x, int y) {
	int posX = x;
	int posY = y;
	if (x == -1) posX=destSurface.width/2-surface.width/2;
	if (y == -1) posY=destSurface.height/2-surface.height/2;

	destSurface.blit(surface, posX, posY);
}
