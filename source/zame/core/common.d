module zame.core.common;

import core.sync.mutex;
import std.variant;
import std.datetime.stopwatch;
import std.format;

public import std.datetime.stopwatch : Duration;

enum Result {
    ok,
    unknown_error,
    unknown_ok,
    unknown,
    animation_not_exists,
    surface_not_found,
    full_capacity_error,
    not_enough_memory,
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
}

struct Vec2 {
    float x, y;
}

struct Point {
    int x;
    int y;
}

struct Size {
    uint w;
    uint h;
}

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
