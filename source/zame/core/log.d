module zame.core.log;

import std.stdio;
import std.file;
import std.datetime;
import std.format;
import core.sync.mutex;
import std.array;

struct LogRecord {
	string type;
	string message;
	SysTime timestamp;

	static LogRecord create(string type, string message) {
		return LogRecord(type, message, Clock.currTime());
	}

	private this(string type, string message, SysTime timestamp) {
		this.type = type;
		this.message = message;
		this.timestamp = timestamp;
	}

	string toString() const {
		return format("[%s][%s] %s", type, timestamp.toISOExtString(), message);
	}
}


interface ILogHandler {
	void handle(LogRecord record);
}

class ConsoleHandler : ILogHandler {
	void handle(LogRecord record) {
		writeln(record.toString());
	}
}

class FileHandler : ILogHandler {
	private string filePath;
	private Mutex m;

	this(string filePath) { this.filePath = filePath; this.m = new Mutex(); }

	void handle(LogRecord record) {
		m.lock();
		try { std.file.append(filePath, record.toString() ~ "\n"); }
		finally { m.unlock(); }
	}
}

class MemoryHandler : ILogHandler {
	private LogRecord[] buffer;
	private Mutex m;

	this() { this.m = new Mutex(); }

	void handle(LogRecord record) {
		m.lock();
		buffer ~= record;
		m.unlock();
	}

	LogRecord[] getLogs() {
		m.lock();
		auto copy = buffer.dup;
		m.unlock();
		return copy;
	}
}

class Logger {
	private ILogHandler[] handlers;
	private Mutex m;

	this() { this.m = new Mutex(); }

	private bool _initialized = false;

	void addHandler(ILogHandler handler) { handlers ~= handler; }

	void init() {
		if (!_initialized) {
			addHandler(new ConsoleHandler());
			_initialized = true;
		}
	}

	void log(string type, string message) {
		init();
		auto record = LogRecord.create(type, message);
		m.lock();
		foreach(h; handlers) {
			h.handle(record);
		}
		m.unlock();
}


	void info(string msg)  { log("INFO", msg); }
	void debug_(string msg) { log("DEBUG", msg); }
	void warn(string msg)  { log("WARN", msg); }
	void error(string msg) { log("ERROR", msg); }
}
