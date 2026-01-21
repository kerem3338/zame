module zame.core.platform;

import core.thread;
import std.stdio;
import std.format;
import std.string;
import std.utf;
import std.file;
import std.variant;
import std.array : replicate;

import zame;

version (Windows) {
	import core.sys.windows.windows;
	import core.sys.windows.commdlg;

	pragma(lib, "comdlg32");
	pragma(lib, "winmm");
}

enum EventType {
	keyPressed,
	keyReleased,
	textInput,
	mouseMoved,
	mouseButtonPressed,
	mouseButtonReleased,
	mouseWheel,
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

struct MouseWheelEvent {
	int delta;
}

struct Event {
	EventType type;
	Window window;
	union {
		KeyEvent key;
		TextInputEvent textInput;
		MouseEvent mouse;
		MouseMoveEvent mouseMoved;
		MouseWheelEvent mouseWheel;
	}
}

struct PlatformCapabilities {
	bool hasSubWindows;
}

class IPlatform {
	abstract string platformName();
	abstract PlatformCapabilities capabilities();

	abstract int createWindow(Window window);
	abstract void processMessages();
	abstract void invalidate();
	abstract void cleanup();
	abstract bool isRunning();
    abstract void exit();
	abstract void setTargetFps(uint fps);
	abstract uint getTargetFps();
	void setInstance(Instance inst) {}
    abstract IAudioDevice getAudioDevice();
    void setIcon(string path) {}
    
    abstract string getClipboard();
    abstract void setClipboard(string text);
}

class Window {
	uint width;
	uint height;
	Surface surface;
	string title;
    string iconPath;
	IPlatform platform;
	Window parent;

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
	Logger logger;
    IAudioDevice audio;
    int mouseX, mouseY;

	this(Window window, IPlatform platform) {
		this.window = window;
		this.platform = platform;

		this.logger = new Logger();
		this.logger.addHandler(new MemoryHandler());
	}

	void doInitJobs() {
        this.audio = this.platform.getAudioDevice();
		this.logger.info(format("Zame Engine v%s (%s)", VERSION, this.platform.platformName()));
	}

	void pushEvent(Event e) {
		eventQueue ~= e;
        if (e.type == EventType.mouseMoved) {
            mouseX = e.mouseMoved.x;
            mouseY = e.mouseMoved.y;
        }
	}

	Event[] pollEvents() {
		auto events = eventQueue.dup;
		eventQueue.length = 0;
		return events;
	}

	void update() {

	}
    
    void exit() {
        platform.exit();
    }
}

void messageBox(string title, string message, bool nonBlocking = false, bool writeToConsole = false) {
    void show() {
        version (Windows) {
            MessageBoxA(
                null,
                message.ptr,
                title.ptr,
                MB_OK | MB_ICONINFORMATION
            );
        }
        else {
            if (writeToConsole) {
                writefln("%s\n%s\n%s",
                    title,
                    replicate("-", title.length),
                    message
                );
            }
        }
    }

    if (nonBlocking) {
        auto t = new Thread(&show);
        t.isDaemon = true;
        t.start();
    } else {
        show();
    }

    if (writeToConsole) {
        writefln("%s\n%s\n%s",
            title,
            replicate("-", title.length),
            message
        );
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
