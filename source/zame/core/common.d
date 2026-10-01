module zame.core.common;

import core.sync.mutex;
import std.variant;
import std.datetime.stopwatch;
import std.format;

public import std.datetime.stopwatch : Duration;

 
/// Operation result status codes 
enum Result {
	ok,
	error,
	unknown_error,
	os_error,
	unknown_ok,
	unknown,
	animation_not_exists,
	surface_not_found,
	full_capacity_error,
	not_enough_memory,
	override_error,
	key_error,
	file_not_found,
	platform_not_supported,
	not_implemented,
	unknown_filesystem_error,
	unknown_device_error,
	device_error
}

enum GraphicsApiType {
	unknown,
	software,   /// CPU software rasterizer
	openGL,     /// Desktop OpenGL
	openGLES,   /// OpenGL ES
	directX,    /// Direct3D / DirectX
	vulkan,     /// Vulkan API
	metal,      /// Apple Metal API
	webGL       /// WebGL / WebGPU
}

struct GraphicsApi {
	GraphicsApiType type = GraphicsApiType.unknown;
	string details;

	this(GraphicsApiType type, string details = "") {
		this.type = type;
		this.details = details;
	}

	string toString() const {
		if (details.length > 0)
			return format("%s (%s)", type, details);
		return format("%s", type);
	}
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

template hasMethod(T, string name, Args...)
{
	enum bool hasMethod =
		__traits(compiles, {
			T t;
			mixin("t." ~ name ~ "(" ~ Args.stringof ~ ");");
		});
}

template hasField(T, string name)
{
	enum bool hasField = __traits(hasMember, T, name);
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

 
struct Vec3 {
	float x, y, z;

	this(float x, float y, float z) {
		this.x = x;
		this.y = y;
		this.z = z;
	}

	string toString() const {
		return format("Vec3(%f,%f,%f)", x, y, z);
	}
}

struct Vec2 {
	float x, y;

	this(float x, float y) pure nothrow @nogc {
		this.x = x;
		this.y = y;
	}
	
	static Vec2 zero() pure nothrow @nogc {
		return Vec2(0.0f, 0.0f);
	}
	
	float length() const {
		import std.math : sqrt;
		return sqrt(x*x + y*y);
	}
	
	Vec2 normalized() const {
		float len = length();
		if (len > 0) {
			return Vec2(x/len, y/len);
		}
		return Vec2.zero();
	}

	this(Point p) pure nothrow @nogc {
		this.x = cast(float)p.x;
		this.y = cast(float)p.y;
	}

	Point asPoint() const pure nothrow @nogc {
		return Point(cast(int)x, cast(int)y);
	}
	
	Vec2 opUnary(string op)() const pure nothrow @nogc if (op == "-") {
		return Vec2(-x, -y);
	}

	Vec2 opBinary(string op)(Vec2 other) const pure nothrow @nogc if (op == "+" || op == "-") {
		mixin("return Vec2(x " ~ op ~ " other.x, y " ~ op ~ " other.y);");
	}

	Vec2 opBinary(string op)(float scalar) const pure nothrow @nogc if (op == "*" || op == "/") {
		mixin("return Vec2(x " ~ op ~ " scalar, y " ~ op ~ " scalar);");
	}

	ref Vec2 opOpAssign(string op)(Vec2 other) pure nothrow @nogc if (op == "+" || op == "-") {
		mixin("x " ~ op ~ "= other.x;");
		mixin("y " ~ op ~ "= other.y;");
		return this;
	}

	ref Vec2 opOpAssign(string op)(float scalar) pure nothrow @nogc if (op == "+" || op == "-") {
		mixin("x " ~ op ~ "= scalar;");
		mixin("y " ~ op ~ "= scalar;");
		return this;
	}
	
	T opCast(T)() const pure nothrow @nogc if (is(T == Point)) {
		return Point(cast(int)x, cast(int)y);
	}

	string toString() const {
		return format("Vec2(%s, %s)", x, y);
	}
}

struct Point {
	int x;
	int y;

	this(int x, int y) pure nothrow @nogc {
		this.x = x;
		this.y = y;
	}

	this(Vec2 v) pure nothrow @nogc {
		this.x = cast(int)v.x;
		this.y = cast(int)v.y;
	}

	T opCast(T)() const pure nothrow @nogc if (is(T == Vec2)) {
		return Vec2(cast(float)x, cast(float)y);
	}
	
	Point opBinary(string op)(Point other) const pure nothrow @nogc if (op == "+" || op == "-") {
		mixin("return Point(x " ~ op ~ " other.x, y " ~ op ~ " other.y);");
	}

	static Point zero() pure nothrow @nogc {
		return Point(0, 0);
	}
}

struct Size {
	uint w;
	uint h;
}

struct Rect {
	int x,y,w,h;

	bool intersects(const Rect other) const {
		return (x < other.x + other.w && x + w > other.x &&
				y < other.y + other.h && y + h > other.y);
	}

	bool contains(Point p) const {
		return (p.x >= x && p.x < x + w &&
				p.y >= y && p.y < y + h);
	}

	Point center() const {
		return Point(x + w/2, y + h/2);
	}

	Point topLeft() const { return Point(x, y); }
    Point topRight() const { return Point(x + w, y); }
    Point bottomLeft() const { return Point(x, y + h); }
    Point bottomRight() const { return Point(x + w, y + h); }
    int bottom() const { return y+h; }
}

struct Color {
	ubyte b;
	ubyte g;
	ubyte r;
	ubyte a = 255;

	this(int r, int g, int b, int a = 255) pure nothrow @nogc {
		this.r = cast(ubyte)r;
		this.g = cast(ubyte)g;
		this.b = cast(ubyte)b;
		this.a = cast(ubyte)a;
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

struct Countdown {
	Duration duration;
	StopWatch watch;

	this(Duration duration, AutoStart autoStart = AutoStart.no) {
		this.duration = duration;
		watch = StopWatch(autoStart);
	}

	void start() {
		watch.start();
	}

	bool isFinished() {
		return watch.peek() >= duration;
	}

	Duration remaining() {
		if (isFinished()) return Duration.zero;
		return duration - watch.peek();
	}

	void reset() {
		watch.reset();
	}
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


struct Camera2D {
	Vec2  position;
	Size  viewport;
	Vec2  target;
	float zoom = 1.0f;

	this(Vec2 pos, Size viewport, float zoom = 1.0f) {
        this.position = pos;
        this.viewport = viewport;
        this.zoom = zoom;
        this.target = Vec2(0, 0);
    }
    
	Point worldToScreen(Vec2 worldPos) const {
		float sx = (worldPos.x - position.x) * zoom;
		float sy = (worldPos.y - position.y) * zoom;
		return Point(safeCast(sx), safeCast(sy));
	}

	Vec2 screenToWorld(Point screenPos) const {
		return Vec2(
			screenPos.x / zoom + position.x,
			screenPos.y / zoom + position.y
		);
	}

	Rect getWorldRect() const {
		return Rect(
			cast(int)position.x,
			cast(int)position.y,
			cast(int)(viewport.w / zoom),
			cast(int)(viewport.h / zoom)
		);
	}

	void move(Vec2 delta) {
		position.x += delta.x;
		position.y += delta.y;
	}
	void centerOn(Vec2 worldPos) {
		position.x = worldPos.x - viewport.w / (2.0f * zoom);
		position.y = worldPos.y - viewport.h / (2.0f * zoom);
	}

	void followTarget(Vec2 targetPos, float smoothness = 0.1f) {
		position.x += (targetPos.x - viewport.w / (2.0f * zoom) - position.x) * smoothness;
		position.y += (targetPos.y - viewport.h / (2.0f * zoom) - position.y) * smoothness;
	}

	private static int safeCast(float v) {
		import std.math : isNaN, isInfinity;
		if (isNaN(v) || isInfinity(v)) return 0;
		if (v > cast(float)int.max)    return int.max;
		if (v < cast(float)int.min)    return int.min;
		return cast(int)v;
	}
}

