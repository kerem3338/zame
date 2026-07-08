module zame.core.common;

import core.sync.mutex;
import std.variant;
import std.datetime.stopwatch;
import std.format;

public import std.datetime.stopwatch : Duration;

/++ 
 * Operation result statuses 
 +/
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
	not_implemented
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
	
	this(float x, float y) {
		this.x = x;
		this.y = y;
	}
	
	static Vec2 zero() {
		return Vec2(0, 0);
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
	
	Vec2 opBinary(string op)(Vec2 other) const if (op == "+" || op == "-") {
		mixin("return Vec2(x " ~ op ~ " other.x, y " ~ op ~ " other.y);");
	}

	Vec2 opBinary(string op)(float scalar) const if (op == "*" || op == "/") {
		mixin("return Vec2(x " ~ op ~ " scalar, y " ~ op ~ " scalar);");
	}

	string toString() const {
		return format("Vec2(%s, %s)", x, y);
	}
}

struct Point {
	int x;
	int y;

	static Point zero() {
		return Point(0,0);
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
}

struct Color {
	ubyte b;
	ubyte g;
	ubyte r;
	ubyte a = 255;

	this(int r, int g, int b, int a = 255) {
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

	this(Duration duration) {
		this.duration = duration;
		watch = StopWatch(AutoStart.yes);
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
