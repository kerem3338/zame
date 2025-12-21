module zame;

import std.conv;
import std.format;
import std.string;
import std.utf;
import std.file;
import std.container : Array;
import std.stdio;
import std.algorithm;
import std.utf;

string getLineTerminator() {
	version (Windows) {
		return "\r\n";
	} else version (Linux) {
		return "\n";
	} else version (MacOS) {
		return "\r";
	} else {
		return "\n";
	}
}


enum Result {
	ok,
	unknown_error,
	unknown
}

struct ResultStatus {
	Result result;
	string message;
}

struct Point {
	int x;
	int y;
}

/**
Size
**/
struct Size {
	uint w;
	uint h;
}

/**
Rectangle, a combination of Point and Size
**/
struct Rect {
	Point location;
	Size  size;

	alias loc  = location;
}

struct Color {
	uint r;
	uint g;
	uint b;
	uint a = 255;
	
}

enum EventType {
	keyPressed,
	keyReleased,
	mouseMoved,
	mouseButtonPressed,
	mouseButtonReleased,
}

struct KeyEvent {
	dchar key;
}

struct MouseMoveEvent {
	int x, y;
}

struct MouseEvent {
	int x, y;
	enum ButtonType { left, right, middle }
	ButtonType button;
}

struct Event {
	EventType type;
	union {
		KeyEvent key;
		MouseEvent mouse;
		MouseMoveEvent mouseMoved;
	}
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

	void blit(Surface src, int destX, int destY, bool useAlpha = true) {
		foreach (y; 0 .. src.height) {
			int dstY = destY + y;
			if (dstY < 0 || dstY >= cast(int)height) continue;

			foreach (x; 0 .. src.width) {
				int dstX = destX + x;
				if (dstX < 0 || dstX >= cast(int)width) continue;

				Color srcColor = src.data[y * src.width + x];

				if (useAlpha && srcColor.a < 255) {
					Color dstColor = this.data[dstY * width + dstX];
					float alpha = srcColor.a / 255.0f;
					uint r = cast(uint)(srcColor.r * alpha + dstColor.r * (1.0f - alpha));
					uint g = cast(uint)(srcColor.g * alpha + dstColor.g * (1.0f - alpha));
					uint b = cast(uint)(srcColor.b * alpha + dstColor.b * (1.0f - alpha));
					this.data[dstY * width + dstX] = Color(r, g, b, 255);
				} else {
					this.data[dstY * width + dstX] = srcColor;
				}
			}
		}
	}
}

class BitmapFont
{
	struct Glyph
	{
		int x;
		int y;
		int w;
		int h;
		int advance;
	}

	string name;
	int size;
	int lineHeight;
	int widthSpacing = 1;

	Surface atlas;
	Glyph[dchar] glyphs;

	this(string atlasPath, string infoPath, int spacing = 1)
	{
		widthSpacing = spacing;
		loadAtlas(atlasPath);
		readInfo(infoPath);
		write(glyphs);
	}

	void loadAtlas(string path)
	{
		atlas = new Surface(1, 1);
		auto res = loadFromPng(atlas, path);
		if (res.result != Result.ok)
			throw new Exception("Failed to load font atlas: " ~ path);
	}

	void readInfo(string path)
	{
		auto lines = readText(path).splitLines;
		size_t i = 0;

		while (i < lines.length && lines[i].strip != "---")
		{
			auto l = lines[i].strip;
			if (l.startsWith("name:str:"))
				name = l["name:str:".length .. $];
			else if (l.startsWith("size:int:"))
				size = l["size:int:".length .. $].to!int;
			else if (l.startsWith("lineHeight:int:"))
				lineHeight = l["lineHeight:int:".length .. $].to!int;
			i++;
		}

		if (i < lines.length && lines[i].strip == "---")
			i++;

		for (; i < lines.length; i++)
		{
			auto l = lines[i].strip;
			if (l.length == 0) continue;

			auto parts = l.split;
			if (parts.length < 2) continue;

			size_t idx = 0;
			dchar ch = decode(l, idx);

			Glyph g;
			foreach (p; parts[1 .. $])
			{
				auto kv = p.split("=");
				if (kv.length != 2) continue;

				final switch(kv[0])
				{
					case "x": g.x = kv[1].to!int; break;
					case "y": g.y = kv[1].to!int; break;
					case "w": g.w = kv[1].to!int; break;
					case "h": g.h = kv[1].to!int; break;
				}
			}

			glyphs[ch] = g;
		}


		if (!('?' in glyphs))
			throw new Exception("BitmapFont requires '?' fallback glyph");
	}

	private float safeScale(int fontSize)
	{
		int maxH = 1;
		foreach (g; glyphs.byValue)
			if (g.h > maxH) maxH = g.h;

		return cast(float)fontSize / maxH;
	}

	private Surface renderNative(string text, Color color)
	{
		int w = 0;
		foreach (dchar c; text)
			w += (c in glyphs ? glyphs[c].w : glyphs['?'].w);

		auto outSurf = new Surface(w, lineHeight);
		outSurf.fill(Color(0,0,0,0));

		int cx = 0;
		foreach (dchar c; text)
		{
			auto g = (c in glyphs) ? glyphs[c] : glyphs['?'];

			if (c == ' ')
			{
				cx += g.w;
				continue;
			}

			for (int y = 0; y < g.h; y++)
			for (int x = 0; x < g.w; x++)
			{
				auto src = atlas.rawData[(g.y+y)*atlas.width + (g.x+x)];
				if (src.r > 240 && src.g > 240 && src.b > 240) continue;

				outSurf.rawData[y*outSurf.width + (cx+x)] =
					Color(color.r, color.g, color.b, 255);
			}

			cx += g.w;
		}

		return outSurf;
	}

	Surface getText(string text, Color color, int fontSize)
	{
		auto native = renderNative(text, color);
		float scale = safeScale(fontSize);

		auto scaled = scaleSurface(
			native,
			cast(int)(native.width * scale),
			fontSize
		);

		return applySafeSpacing(scaled, text, scale);
	}

	private Surface applySafeSpacing(Surface src, string text, float scale)
	{
		int count = text.length.to!int;
		if (count <= 1) return src;

		int spacing = cast(int)(widthSpacing * scale);

		int avgGlyphW = src.width / count;
		int maxSpacing = avgGlyphW / 4;
		if (spacing > maxSpacing)
			spacing = maxSpacing;

		if (spacing <= 0)
			return src;

		int finalW = src.width + spacing * (count - 1);
		auto outSurf = new Surface(finalW, src.height);
		outSurf.fill(Color(0,0,0,0));

		int sx = 0;
		int dx = 0;

		foreach (i, dchar c; text)
		{
			auto g = (c in glyphs) ? glyphs[c] : glyphs['?'];
			int gw = cast(int)(g.w * scale);

			for (int y = 0; y < src.height; y++)
			for (int x = 0; x < gw; x++)
				outSurf.rawData[y*finalW + dx+x] =
					src.rawData[y*src.width + sx+x];

			sx += gw;
			dx += gw;
			if (i < count-1) dx += spacing;
		}

		return outSurf;
	}

}






class GenericBitmapFont
{
	struct Glyph
	{
		int width;
		int height;
		bool[][] pixels;
	}

	string path;
	string name;
	int width;
	int height;

	Glyph[dchar] glyphs;

	this(string path)
	{
		this.path = path;
		readFont();
	}

	void readFont()
	{
		auto text = readText(path);
		auto lines = text.splitLines;
		size_t i = 0;

		while (i < lines.length && lines[i] != "---")
		{
			auto l = lines[i];
			if (l.startsWith("name:str:"))
				name = l["name:str:".length .. $];
			else if (l.startsWith("width:int:"))
				width = l["width:int:".length .. $].to!int;
			else if (l.startsWith("height:int:"))
				height = l["height:int:".length .. $].to!int;
			i++;
		}

		if (i < lines.length && lines[i] == "---")
			i++;

		while (i < lines.length)
		{
			if (lines[i].length == 0) { i++; continue; }

			auto header = lines[i++];
			auto parts = header.split(";")[0].split(",");
			dchar[] chars;

			foreach (p; parts)
				if (!p.empty)
					chars ~= cast(dchar)p[0];

			string[] bmpLines;
			while (i < lines.length && lines[i].length > 0 && !lines[i].endsWith(";"))
				bmpLines ~= lines[i++];

			if (bmpLines.length == 0) continue;

			Glyph g;
			g.width  = bmpLines[0].length.to!int;
			g.height = bmpLines.length.to!int;
			g.pixels.length = g.height;

			foreach (y; 0 .. g.height)
			{
				g.pixels[y].length = g.width;
				foreach (x; 0 .. g.width)
					g.pixels[y][x] = (bmpLines[y][x] == 'x');
			}

			foreach (c; chars)
				glyphs[c] = g;
		}
	}

	Surface getText(string text, Color color, uint fontSize)
	{
		int totalW = 0;
		foreach (dchar c; text)
		{
			auto g = (c in glyphs) ? glyphs[c] : glyphs['?'];
			totalW += fontSize * g.width / height;
		}

		auto outSurfSurf = new Surface(totalW, fontSize);
		outSurfSurf.fill(Color(0,0,0,0));

		int cx = 0;

		foreach (dchar c; text)
		{
			auto g = (c in glyphs) ? glyphs[c] : glyphs['?'];

			int scaleX = fontSize * g.width / height / g.width;
			int scaleY = fontSize / g.height;

			foreach (y; 0 .. g.height)
			foreach (x; 0 .. g.width)
			{
				if (!g.pixels[y][x]) continue;

				for (int sy = 0; sy < scaleY; sy++)
				for (int sx = 0; sx < scaleX; sx++)
				{
					outSurfSurf.setPixel(
						Point(cx + x * scaleX + sx,
							  y * scaleY + sy),
						color
					);
				}
			}

			cx += fontSize * g.width / height;
		}

		return outSurfSurf;
	}
}

class IPlatform {

}

class Window {
	uint width;
	uint height;
	Surface surface;
	string title;

	this(uint width, uint height, string title="Zame Engine") {
		this.width = width;
		this.height = height;
		surface = new Surface(width, height);
		title = title;
	}

	int createWindow() { return 0; }
}

class Instance {
	Window window;
	string[string] config;
	Event[] eventQueue;
	IPlatform platform;
	
	this(Window window, IPlatform platform) {
		this.window = window;
		this.platform = platform;
	}

	void pushEvent(Event e) {
		eventQueue ~= e;
	}

	Event[] pollEvents() {
		auto events = eventQueue.dup;
		eventQueue.length = 0;
		return events;
	}

	void update() {

	}
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



ResultStatus loadFromPng(ref Surface dest, string filePath)
{
	import gamut;

	Image img;
	img.loadFromFile(
		filePath,
		LOAD_RGB | LOAD_ALPHA | LOAD_8BIT | LOAD_NO_PREMUL
	);

	if (img.isError)
		return ResultStatus(Result.unknown_error, img.errorMessage.idup);

	if (img.type != PixelType.rgba8)
		return ResultStatus(Result.unknown, "PNG is not RGBA8");

	dest.resize(img.width, img.height);

	foreach (y; 0 .. img.height)
	{
		ubyte* scan = cast(ubyte*) img.scanptr(y);

		foreach (x; 0 .. img.width)
		{
			uint r = scan[x * 4 + 0];
			uint g = scan[x * 4 + 1];
			uint b = scan[x * 4 + 2];
			uint a = scan[x * 4 + 3];

			dest.setPixel(Point(x, y), Color(r, g, b, a));
		}
	}

	return ResultStatus(Result.ok, "PNG Image loaded");
}

