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
import std.variant;
import std.array;
import std.datetime.stopwatch;
import std.math;

version (Windows) {
	import core.sys.windows.windows;
	import core.sys.windows.commdlg;
	
	pragma(lib, "comdlg32");
	pragma(lib, "winmm");
}

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

enum Colors: Color {
	black = Color(0, 0, 0),
	white = Color(255, 255, 255),
	red = Color(255, 0 , 0),
	green = Color(0, 255, 0),
	blue = Color(0, 0, 255)
}

enum Result {
	ok, // Ok
	unknown_error, // Unknown Error
	unknown_ok, // It worked but, no idea how
	unknown, // Result is unknown
	animation_not_exists // Animation Does Not Exists
}

struct ResultStatus {
	Result result;
	string message;
	Variant[string] fields;
	string file;
	size_t line;

	this(Result res, string msg = "", string file = __FILE__, size_t line = __LINE__) {
		this.result = res;
		this.message = msg;
		this.file = file;
		this.line = line;
	}

	@property bool ok() const { return result == Result.ok; }
	alias ok this;

	ResultStatus withField(T)(string name, T value) {
		fields[name] = Variant(value);
		return this;
	}

	auto getField(T)(string name) {
		return fields[name].get!T;
	}

	auto opDispatch(string name)() {
		return fields[name];
	}

	void opDispatch(string name, T)(T value) {
		fields[name] = Variant(value);
	}

	void toString(scope void delegate(const(char)[]) sink) const {
		import std.format : formattedWrite;
		sink.formattedWrite("%s", result);
		if (message.length) {
			sink(": ");
			sink(message);
		}
	}
}

/**
  Template version of ResultStatus that can carry a payload,
  similar to std::expected in modern C++.
**/
struct Outcome(T) {
	ResultStatus status;
	T value;
	
	alias status this;

	this(T val) {
		status = ResultStatus(Result.ok);
		this.value = val;
	}

	this(Result res, string msg = "") {
		status = ResultStatus(res, msg);
	}

	this(ResultStatus status) {
		this.status = status;
	}

	void toString(scope void delegate(const(char)[]) sink) const {
		import std.format : formattedWrite;
		if (status.ok) {
			sink.formattedWrite("Success(%s)", value);
		} else {
			sink.formattedWrite("Failure(%s)", status.result);
			if (status.message.length) {
				sink(": ");
				sink(status.message);
			}
		}
	}
}

auto success(T)(T value) {
    return Outcome!T(value);
}

auto failure(T)(Result res, string msg = "") {
    return Outcome!T(res, msg);
}

auto failure(T)(ResultStatus status) {
    return Outcome!T(status);
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
	alias x=location.x;
	alias y=location.y;
	alias w=size.w;
	alias h=size.h;
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
	textInput,
	mouseMoved,
	mouseButtonPressed,
	mouseButtonReleased,
}

enum KeyCode : ushort
{
	Unknown = 0,

	A, B, C, D, E, F, G, H, I, J, K, L, M,
	N, O, P, Q, R, S, T, U, V, W, X, Y, Z,

	Num0, Num1, Num2, Num3, Num4,
	Num5, Num6, Num7, Num8, Num9,

	F1, F2, F3, F4, F5, F6,
	F7, F8, F9, F10, F11, F12,

	Escape, Tab, CapsLock,
	ShiftLeft, ShiftRight,
	CtrlLeft, CtrlRight,
	AltLeft, AltRight,
	SuperLeft, SuperRight,
	Enter, Backspace, Space,

	ArrowUp, ArrowDown, ArrowLeft, ArrowRight,

	Insert, Delete, Home, End, PageUp, PageDown,
	Pause, PrintScreen, ScrollLock
}

enum Modifiers : ushort
{
	None  = 0,
	Shift = 1 << 0,
	Ctrl  = 1 << 1,
	Alt   = 1 << 2,
	Super = 1 << 3
}

struct KeyEvent
{
	KeyCode code;
	Modifiers mods;
	bool pressed;
}

struct TextInputEvent
{
	dchar character;
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
		TextInputEvent textInput;
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

	void blit(Surface src, Point where) {
		blit(src, where.x, where.y);
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
}

struct Timer {
	Duration interval;
	StopWatch watch;

	this(Duration interval) {
		this.interval = interval;
		watch = StopWatch(AutoStart.yes);
	}

	bool tick() {
		if (watch.peek() >= interval) {
			watch.reset();
			return true;
		}
		return false;
	}

	void reset() {
		watch.reset();
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
				// Assume white is transparent background, black/colors are text
				// Intensity (0-255) will be our alpha mask. 
				// 0 (black) -> full alpha, 255 (white) -> zero alpha
				int intensity = 255 - ((src.r + src.g + src.b) / 3);
				if (intensity <= 0) continue;

				uint finalAlpha = cast(uint)(color.a * intensity / 255);
				if (finalAlpha == 0) continue;

				outSurf.rawData[y*outSurf.width + (cx+x)] =
					Color(color.r, color.g, color.b, finalAlpha);
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
	abstract string platformName();

	abstract int createWindow(Window window);
	abstract void processMessages();
	abstract void invalidate();
	abstract void cleanup();
	abstract bool isRunning();
	void setInstance(Instance inst) {}
}

class Window {
	uint width;
	uint height;
	Surface surface;
	string title;
	IPlatform platform;

	this(uint width, uint height, string title="Zame Engine") {
		this.width = width;
		this.height = height;
		surface = new Surface(width, height);
		this.title = title;
	}

	int createWindow() {
		return platform.createWindow(this);
	}
}

class Instance {
	Window window;
	Variant[string] config;
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

abstract class Scene {
	SceneManager sceneManager;
	
	@property Instance instance() { return sceneManager ? sceneManager.instance : null; }

	abstract void start();
	
	abstract void stop();
	
	abstract void update(float deltaTime);
	
	abstract void render(Surface surface);
	
	abstract void onEvent(Event event);

	override string toString() {
		return "Scene()";
	}
}

class SceneManager {
private:
	Scene currentScene;
	Scene nextScene;
	bool shouldChangeScene = false;
	Instance _instance;
	
public:
	@property Instance instance() { return _instance; }

	this(Instance instance) {
		this._instance = instance;
		currentScene = null;
		nextScene = null;
	}
	
	void changeScene(Scene newScene) {
		nextScene = newScene;
		shouldChangeScene = true;
	}
	
	void update(float deltaTime) {
		if (shouldChangeScene && nextScene !is null) {
			if (currentScene !is null) {
				currentScene.stop();
			}
			
			currentScene = nextScene;
			currentScene.sceneManager = this;
			currentScene.start();
			
			nextScene = null;
			shouldChangeScene = false;
		}
		
		if (currentScene !is null) {
			currentScene.update(deltaTime);
		}
	}
	
	void render(Surface surface) {
		if (currentScene !is null) {
			currentScene.render(surface);
		}
	}
	
	void handleEvent(Event event) {
		if (currentScene !is null) {
			currentScene.onEvent(event);
		}
	}
	
	Scene getCurrentScene() {
		return currentScene;
	}
	
	bool hasScene() {
		return currentScene !is null;
	}

	override string toString() {
		return "SceneManager(currentScene: "~currentScene.toString()~")";
	}
}

class ResourceManager {
	Variant[string] data;

	this() {}
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

void messageBox(string title, string message, bool writeToConsole = false) {
	scope (exit) {
		if (writeToConsole)
			writefln("%s\n%s\n%s", title, replicate("-", title.length), message);
	}
	version (Windows) {
		MessageBoxA(
			null,
			message.ptr,
			title.ptr,
			MB_OK
		);
	} else {
		writeToConsole = true;
	}
}

string getFileDialog(
	string title,
	string message,
	string[] filters = ["*.*"],
	bool noDirectory = false,
	bool mustExists = false,
	bool enforceFilter = false
) {
	string path;

	version (Windowsd) {
		wchar[260] fileBuffer;

		string filterStr;
		foreach (f; filters) {
			filterStr ~= f ~ "\0" ~ f ~ "\0";
		}
		filterStr ~= "\0";

		OPENFILENAMEW ofn;
		ofn.lStructSize  = OPENFILENAMEW.sizeof;
		ofn.lpstrTitle  = toUTF16z(title);
		ofn.hwndOwner = null;
		ofn.lpstrFilter = toUTF16z(filterStr);
		ofn.lpstrFile   = fileBuffer.ptr;
		ofn.nMaxFile    = fileBuffer.length;

		ofn.Flags = OFN_EXPLORER | OFN_PATHMUSTEXIST;

		if (mustExists)
			ofn.Flags |= OFN_FILEMUSTEXIST;

		if (noDirectory)
			ofn.Flags |= OFN_NOVALIDATE;

		if (enforceFilter)
			ofn.Flags |= OFN_EXTENSIONDIFFERENT;

		if (GetOpenFileNameW(&ofn)) {
			return to!string(fileBuffer.ptr);
		}

		return "";
	}
	else {
		writefln("%s\n%s", title, message);
		while (true) {
			writef("Path %s: ", filters);
			path = readln().strip;

			if (mustExists && !path.exists)
				messageBox("Error","Given path does not exist.");
			else if (noDirectory && path.isDir)
				messageBox("Error","Given path must be a file.");
			else
				break;
		}
		return path;
	}
}
