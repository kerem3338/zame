/+
Raylib Platform For Zame
+/
module platforms.praylib;

import zame;
import std;

import raylib;
alias RLColor = raylib.raylib_types.Color;

KeyCode toKeyCode(int rayKey)
{
	import raylib : KeyboardKey;
	with (KeyboardKey)
	{
		switch(rayKey)
		{
			case KEY_A: return KeyCode.A;
			case KEY_B: return KeyCode.B;
			case KEY_C: return KeyCode.C;
			case KEY_D: return KeyCode.D;
			case KEY_E: return KeyCode.E;
			case KEY_F: return KeyCode.F;
			case KEY_G: return KeyCode.G;
			case KEY_H: return KeyCode.H;
			case KEY_I: return KeyCode.I;
			case KEY_J: return KeyCode.J;
			case KEY_K: return KeyCode.K;
			case KEY_L: return KeyCode.L;
			case KEY_M: return KeyCode.M;
			case KEY_N: return KeyCode.N;
			case KEY_O: return KeyCode.O;
			case KEY_P: return KeyCode.P;
			case KEY_Q: return KeyCode.Q;
			case KEY_R: return KeyCode.R;
			case KEY_S: return KeyCode.S;
			case KEY_T: return KeyCode.T;
			case KEY_U: return KeyCode.U;
			case KEY_V: return KeyCode.V;
			case KEY_W: return KeyCode.W;
			case KEY_X: return KeyCode.X;
			case KEY_Y: return KeyCode.Y;
			case KEY_Z: return KeyCode.Z;

			case KEY_ZERO: return KeyCode.Num0;
			case KEY_ONE:  return KeyCode.Num1;
			case KEY_TWO:  return KeyCode.Num2;
			case KEY_THREE:return KeyCode.Num3;
			case KEY_FOUR: return KeyCode.Num4;
			case KEY_FIVE: return KeyCode.Num5;
			case KEY_SIX:  return KeyCode.Num6;
			case KEY_SEVEN:return KeyCode.Num7;
			case KEY_EIGHT:return KeyCode.Num8;
			case KEY_NINE: return KeyCode.Num9;

			case KEY_ESCAPE: return KeyCode.Escape;
			case KEY_TAB:    return KeyCode.Tab;
			case KEY_CAPS_LOCK: return KeyCode.CapsLock;
			case KEY_LEFT_SHIFT:  return KeyCode.ShiftLeft;
			case KEY_RIGHT_SHIFT: return KeyCode.ShiftRight;
			case KEY_LEFT_CONTROL: return KeyCode.CtrlLeft;
			case KEY_RIGHT_CONTROL:return KeyCode.CtrlRight;
			case KEY_LEFT_ALT: return KeyCode.AltLeft;
			case KEY_RIGHT_ALT:return KeyCode.AltRight;
			case KEY_ENTER: return KeyCode.Enter;
			case KEY_BACKSPACE: return KeyCode.Backspace;
			case KEY_SPACE: return KeyCode.Space;

			case KEY_UP: return KeyCode.ArrowUp;
			case KEY_DOWN: return KeyCode.ArrowDown;
			case KEY_LEFT: return KeyCode.ArrowLeft;
			case KEY_RIGHT: return KeyCode.ArrowRight;

			case KEY_F1: return KeyCode.F1;
			case KEY_F2: return KeyCode.F2;
			case KEY_F3: return KeyCode.F3;
			case KEY_F4: return KeyCode.F4;
			case KEY_F5: return KeyCode.F5;
			case KEY_F6: return KeyCode.F6;
			case KEY_F7: return KeyCode.F7;
			case KEY_F8: return KeyCode.F8;
			case KEY_F9: return KeyCode.F9;
			case KEY_F10:return KeyCode.F10;
			case KEY_F11:return KeyCode.F11;
			case KEY_F12:return KeyCode.F12;

			default: return KeyCode.Unknown;
		}
	}
}

Modifiers getModifiers()
{
	import raylib : KeyboardKey, IsKeyDown;
	with (KeyboardKey)
	{
		Modifiers mods = Modifiers.None;

		if (IsKeyDown(KEY_LEFT_SHIFT) || IsKeyDown(KEY_RIGHT_SHIFT))
			mods |= Modifiers.Shift;
		if (IsKeyDown(KEY_LEFT_CONTROL) || IsKeyDown(KEY_RIGHT_CONTROL))
			mods |= Modifiers.Ctrl;
		if (IsKeyDown(KEY_LEFT_ALT) || IsKeyDown(KEY_RIGHT_ALT))
			mods |= Modifiers.Alt;
		if (IsKeyDown(KEY_LEFT_SUPER) || IsKeyDown(KEY_RIGHT_SUPER))
			mods |= Modifiers.Super;

		return mods;
	}
}

class RaylibTexture : ITexture {
	Texture2D tex;
	this(Texture2D t) { this.tex = t; }
	uint width() const { return cast(uint)tex.width; }
	uint height() const { return cast(uint)tex.height; }
	void* handle() { return cast(void*)&tex; }
	~this() {
		UnloadTexture(tex);
	}
}

alias ZColor = zame.core.common.Color;
alias ZColors = zame.core.graphics.Colors;

class RaylibGraphics : IGraphics {
	private Rect clipRect;
	private bool clipping = false;
	private Texture2D[Surface] surfaceTextureCache;

	private pragma(inline, true) RLColor toRL(ZColor c) pure nothrow @nogc {
		return RLColor(c.r, c.g, c.b, c.a);
	}

	void begin() {
		BeginDrawing();
	}

	void end() {
		EndDrawing();
	}

	void clear(ZColor color) {
		ClearBackground(toRL(color));
	}

	void setClip(Rect rect) {
		clipRect = rect;
		clipping = true;
		BeginScissorMode(rect.x, rect.y, rect.w, rect.h);
	}

	void resetClip() {
		if (clipping) {
			EndScissorMode();
			clipping = false;
		}
	}

	Rect getClipRect() const { return clipRect; }
	bool isClipping() const { return clipping; }

	void drawPoint(Point p, ZColor color) {
		DrawPixel(p.x, p.y, toRL(color));
	}

	void drawLine(Point p0, Point p1, ZColor color, int thickness = 1) {
		DrawLineEx(Vector2(p0.x, p0.y), Vector2(p1.x, p1.y), cast(float)thickness, toRL(color));
	}

	void drawDottedLine(Point p0, Point p1, ZColor color, int dotLen = 5, int gapLen = 5, int thickness = 1) {
		float dx = cast(float)(p1.x - p0.x);
		float dy = cast(float)(p1.y - p0.y);
		float dist = sqrt(dx * dx + dy * dy);
		if (dist <= 0) return;

		float nx = dx / dist;
		float ny = dy / dist;
		float curr = 0;
		while (curr < dist) {
			float segEnd = min(curr + dotLen, dist);
			DrawLineEx(
				Vector2(p0.x + nx * curr, p0.y + ny * curr),
				Vector2(p0.x + nx * segEnd, p0.y + ny * segEnd),
				cast(float)thickness,
				toRL(color)
			);
			curr += dotLen + gapLen;
		}
	}

	void drawRect(Rect rect, ZColor color) {
		DrawRectangle(rect.x, rect.y, rect.w, rect.h, toRL(color));
	}

	void drawRectOutline(Rect rect, ZColor color, uint thickness = 1) {
		DrawRectangleLinesEx(Rectangle(rect.x, rect.y, rect.w, rect.h), cast(float)thickness, toRL(color));
	}

	void drawCircle(Point center, int radius, ZColor color) {
		DrawCircleLines(center.x, center.y, cast(float)radius, toRL(color));
	}

	void drawFilledCircle(Point center, int radius, ZColor color) {
		DrawCircle(center.x, center.y, cast(float)radius, toRL(color));
	}

	void drawPolygon(Point[] points, ZColor color, int thickness = 1) {
		if (points.length < 2) return;
		foreach (i; 0 .. points.length) {
			auto p1 = points[i];
			auto p2 = points[(i + 1) % points.length];
			drawLine(p1, p2, color, thickness);
		}
	}

	void drawFilledPolygon(Point[] points, ZColor color) {
		if (points.length < 3) return;
		Vector2 center = Vector2(0, 0);
		foreach (p; points) {
			center.x += p.x;
			center.y += p.y;
		}
		center.x /= points.length;
		center.y /= points.length;
		foreach (i; 0 .. points.length) {
			auto p1 = points[i];
			auto p2 = points[(i + 1) % points.length];
			DrawTriangle(center, Vector2(p1.x, p1.y), Vector2(p2.x, p2.y), toRL(color));
		}
	}

	private Texture2D getOrUploadSurfaceTexture(Surface src) {
		if (auto pTex = src in surfaceTextureCache) {
			return *pTex;
		}
		Image img = GenImageColor(cast(int)src.width, cast(int)src.height, RLColor(0, 0, 0, 0));
		ubyte* data = cast(ubyte*)img.data;
		auto raw = src.rawData;
		foreach (i; 0 .. raw.length) {
			auto c = raw[i];
			size_t idx = i * 4;
			data[idx + 0] = cast(ubyte)c.r;
			data[idx + 1] = cast(ubyte)c.g;
			data[idx + 2] = cast(ubyte)c.b;
			data[idx + 3] = cast(ubyte)c.a;
		}
		Texture2D tex = LoadTextureFromImage(img);
		UnloadImage(img);
		surfaceTextureCache[src] = tex;
		return tex;
	}

	void drawSurface(Surface src, int x, int y, bool useAlpha = true, ubyte globalAlpha = 255) {
		if (src is null) return;
		Texture2D tex = getOrUploadSurfaceTexture(src);
		RLColor tint = RLColor(255, 255, 255, globalAlpha);
		DrawTexture(tex, x, y, tint);
	}

	void drawSurfaceRotated(Surface src, int x, int y, float angleRadians) {
		if (src is null) return;
		Texture2D tex = getOrUploadSurfaceTexture(src);
		float angleDeg = angleRadians * 180.0f / std.math.PI;
		Rectangle srcR = Rectangle(0, 0, tex.width, tex.height);
		Rectangle dstR = Rectangle(x, y, tex.width, tex.height);
		Vector2 origin = Vector2(tex.width / 2.0f, tex.height / 2.0f);
		DrawTexturePro(tex, srcR, dstR, origin, angleDeg, RLColor(255, 255, 255, 255));
	}

	void drawSurfaceScaled(Surface src, Rect destRect) {
		if (src is null) return;
		Texture2D tex = getOrUploadSurfaceTexture(src);
		Rectangle srcR = Rectangle(0, 0, tex.width, tex.height);
		Rectangle dstR = Rectangle(destRect.x, destRect.y, destRect.w, destRect.h);
		DrawTexturePro(tex, srcR, dstR, Vector2(0, 0), 0.0f, RLColor(255, 255, 255, 255));
	}

	void drawTexture(ITexture texture, Rect srcRect, Rect destRect, ZColor tint = ZColors.white) {
		if (texture is null) return;
		Texture2D* rlTex = cast(Texture2D*)texture.handle();
		if (rlTex is null) return;
		Rectangle srcR = Rectangle(srcRect.x, srcRect.y, srcRect.w, srcRect.h);
		Rectangle dstR = Rectangle(destRect.x, destRect.y, destRect.w, destRect.h);
		DrawTexturePro(*rlTex, srcR, dstR, Vector2(0, 0), 0.0f, toRL(tint));
	}

	void cleanup() {
		foreach (ref tex; surfaceTextureCache) {
			UnloadTexture(tex);
		}
		surfaceTextureCache.clear();
	}
}

class RaylibPlatform : IPlatform {
	Surface surfaceRef;
	Instance instanceRef;
	Window windowRef;
	RaylibGraphics graphicsBackend;

	Image image;
	Texture2D texture;
	IAudioDevice audioDevice;

	bool initialized = false;
	bool shouldQuit = false;

	override IGraphics getGraphics(Window window) {
		if (graphicsBackend is null) {
			graphicsBackend = new RaylibGraphics();
		}
		return graphicsBackend;
	}

	override string platformName() {
		return PlatformName.raylib;
	}

	override PlatformCapabilities capabilities() {
		PlatformCapabilities p;
		p.hasSubWindows = false;
		p.canMoveWindow = true;
		return p;
	}

	override int createWindow(Window window) {
		windowRef = window;
		surfaceRef = window.surface;

		import raylib : SetConfigFlags, ConfigFlags;
		SetConfigFlags(ConfigFlags.FLAG_VSYNC_HINT);

		InitWindow(window.width, window.height, window.title.ptr);
		SetExitKey(KeyboardKey.KEY_NULL);

		if (!IsWindowReady())
			return -1;

		if (windowRef.settings.get("window_resizable", true)) {
			SetWindowState(ConfigFlags.FLAG_WINDOW_RESIZABLE);
		}
		
		image = GenImageColor(
			cast(int)surfaceRef.width,
			cast(int)surfaceRef.height,
			RLColor(0, 0, 0, 0)
		);

		texture = LoadTextureFromImage(image);
		initialized = true;

		audioDevice = new RaylibAudioDevice();
		audioDevice.init();

		instanceRef.logger.info("Window created successfully");
		return 0;
	}

	override bool updateWindowSettings() {
		import raylib: ConfigFlags;
		// check for resizing
		if (windowRef.settings.get("window_resizable", true)) {
			SetWindowState(ConfigFlags.FLAG_WINDOW_RESIZABLE);
		} else {
			ClearWindowState(ConfigFlags.FLAG_WINDOW_RESIZABLE);
		}

		return true;
	}

	override void moveWindow(Window window, int x, int y) {
		SetWindowPosition(x, y);
		window.position.x = x;
		window.position.y = y;
	}

	override DisplayInfo[] getDisplays() {
        DisplayInfo[] result;
        int count = GetMonitorCount();
        for (int i = 0; i < count; i++) {
            DisplayInfo info;
            info.name = fromStringz(GetMonitorName(i)).idup;
            info.size = Size(GetMonitorWidth(i), GetMonitorHeight(i));
            Vector2 pos = GetMonitorPosition(i);
            info.position = Point(cast(int)pos.x, cast(int)pos.y);
            info.isPrimary = (i == 0);
            info.refreshRate = 0;
            result ~= info;
        }
        return result;
    }

    override DisplayInfo getPrimaryDisplay() {
        auto displays = getDisplays();
        foreach (d; displays) {
            if (d.isPrimary) return d;
        }
        if (displays.length > 0) return displays[0];
        return DisplayInfo.init;
    }

	void setWindowTitle(string title) {
		SetWindowTitle(title.ptr);
	}

	override void setInstance(Instance inst) {
		this.instanceRef = inst;
	}

	override void setTargetFps(uint fps) {
		// Do not call Raylib's SetTargetFPS() because it uses a CPU busy-wait spinlock.
		// Frame rate throttling is handled cleanly via VSync and engine Thread.sleep().
		this.targetFps = fps;
	}

	override uint getTargetFps() {
		return this.targetFps;
	}

	uint targetFps = 60;

	void handleKeyboard() {
		if (instanceRef is null)
			return;

		int rayKey = GetKeyPressed();
		while (rayKey != 0) {
			KeyEvent ke;
			ke.code = toKeyCode(rayKey);
			ke.mods = getModifiers();
			ke.pressed = true;
			instanceRef.pushEvent(Event(EventType.keyPressed, windowRef, ke));

			rayKey = GetKeyPressed();
		}

		int charCode = GetCharPressed();
		while (charCode != 0) {
			TextInputEvent te;
			te.character = cast(dchar)charCode;
			
			Event e;
			e.type = EventType.textInput;
			e.window = windowRef;
			e.textInput = te;
			instanceRef.pushEvent(e);

			charCode = GetCharPressed();
		}
	}




	override void processMessages() {
		if (WindowShouldClose()) {
			shouldQuit = true;
			return;
		}

		handleKeyboard();

		if (instanceRef !is null && surfaceRef !is null) {
			Vector2 mouse = GetMousePosition();

			int winW = GetScreenWidth();
			int winH = GetScreenHeight();

			int sx = cast(int)(mouse.x * surfaceRef.width / winW);
			int sy = cast(int)(mouse.y * surfaceRef.height / winH);

			if (sx < 0) sx = 0;
			if (sy < 0) sy = 0;
			if (sx >= surfaceRef.width)  sx = surfaceRef.width - 1;
			if (sy >= surfaceRef.height) sy = surfaceRef.height - 1;

			Event e;
			e.type = EventType.mouseMoved;
			e.window = windowRef;
			e.mouseMoved = MouseMoveEvent(sx, sy);
			instanceRef.pushEvent(e);

			
			import raylib : MouseButton, IsMouseButtonPressed, IsMouseButtonReleased;
			MouseButton[3] buttons = [MouseButton.MOUSE_BUTTON_LEFT, MouseButton.MOUSE_BUTTON_RIGHT, MouseButton.MOUSE_BUTTON_MIDDLE];
			MouseEvent.ButtonType[3] types = [MouseEvent.ButtonType.left, MouseEvent.ButtonType.right, MouseEvent.ButtonType.middle];

			foreach (i; 0 .. 3) {
				if (IsMouseButtonPressed(buttons[i])) {
					Event be;
					be.type = EventType.mouseButtonPressed;
					be.window = windowRef;
					be.mouse = MouseEvent(sx, sy, types[i]);
					instanceRef.pushEvent(be);
				}
				if (IsMouseButtonReleased(buttons[i])) {
					Event be;
					be.type = EventType.mouseButtonReleased;
					be.window = windowRef;
					be.mouse = MouseEvent(sx, sy, types[i]);
					instanceRef.pushEvent(be);
				}
			}

			
			import raylib : GetMouseWheelMove;
			float wheel = GetMouseWheelMove();
			if (wheel != 0) {
				Event we;
				we.type = EventType.mouseWheel;
				we.window = windowRef;
				we.mouseWheel.delta = cast(int)(wheel * 120);
				instanceRef.pushEvent(we);
			}
		}
	}

	void updateSurfaceToTexture() {
		if (!initialized || surfaceRef is null)
			return;

		ubyte* data = cast(ubyte*)image.data;

		foreach (i; 0 .. surfaceRef.rawData.length) {
			auto c = surfaceRef.rawData[i]; // zame.Color (BGRA)
			size_t idx = i * 4;

			data[idx + 0] = cast(ubyte)c.r;
			data[idx + 1] = cast(ubyte)c.g;
			data[idx + 2] = cast(ubyte)c.b;
			data[idx + 3] = cast(ubyte)c.a;
		}

		UpdateTexture(texture, image.data);
	}

	override void invalidate() {
		if (!initialized)
			return;

		updateSurfaceToTexture();

		BeginDrawing();
		ClearBackground(RLColor(0, 0, 0, 255)); // BLACK

		float sx = cast(float)GetScreenWidth() / surfaceRef.width;
		float sy = cast(float)GetScreenHeight() / surfaceRef.height;
		float scale = min(sx, sy);

		DrawTextureEx(
			texture,
			Vector2(0, 0),
			0.0f,
			scale,
			RLColor(255, 255, 255, 255) // WHITE
		);

		EndDrawing();
	}

	override void cleanup() {
		if (graphicsBackend !is null) {
			graphicsBackend.cleanup();
			graphicsBackend = null;
		}

		if (initialized) {
			if (audioDevice !is null) audioDevice.cleanup();
			UnloadTexture(texture);
			UnloadImage(image);
			initialized = false;
		}

		CloseWindow();
		instanceRef.logger.info("Cleanup Done.");
	}

	override bool isRunning() {
		return !shouldQuit;
	}

	override void exit() {
		shouldQuit = true;
	}

	override IAudioDevice getAudioDevice() {
		if (audioDevice is null) audioDevice = new NullAudioDevice();
		return audioDevice;
	}

	override string getClipboard() {
		import std.string : fromStringz;
		const(char)* ptr = GetClipboardText();
		if (ptr is null) return "";
		return ptr.fromStringz.idup;
	}

	override void setClipboard(string text) {
		import std.string : toStringz;
		SetClipboardText(text.toStringz);
	}

	override void showMouse(bool visible) {
		if (visible) ShowCursor();
		else HideCursor();
	}

	override DeviceInfo getDeviceInfo() {
		import std.string : fromStringz;

		DeviceInfo info;
		info.platformName = PlatformName.raylib;
		info.graphicsApi  = GraphicsApi(GraphicsApiType.openGL, "Raylib");
		info.fillBuildFlags();

		int monitorCount = GetMonitorCount();
		if (monitorCount > 0) {
			const(char)* monName = GetMonitorName(0);
			if (monName !is null)
				info.gpuModel = monName.fromStringz.idup;
		}
		if (info.gpuModel.length == 0)
			info.gpuModel = "Unknown GPU";

		version (Windows) {
			import core.sys.windows.windows;
			import core.sys.windows.winreg;

			uint major = 0, minor = 0, build = 0;
			string prodName;

			HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
			if (hNtdll !is null) {
				alias pfnRtlGetVersion = extern(Windows) LONG function(void*);
				struct RTL_OSVERSIONINFOEXW {
					DWORD dwOSVersionInfoSize;
					DWORD dwMajorVersion;
					DWORD dwMinorVersion;
					DWORD dwBuildNumber;
					DWORD dwPlatformId;
					WCHAR[128] szCSDVersion;
					WORD wServicePackMajor;
					WORD wServicePackMinor;
					WORD wSuiteMask;
					BYTE wProductType;
					BYTE wReserved;
				}
				auto pRtlGetVersion = cast(pfnRtlGetVersion) GetProcAddress(hNtdll, "RtlGetVersion");
				if (pRtlGetVersion !is null) {
					RTL_OSVERSIONINFOEXW rovi;
					rovi.dwOSVersionInfoSize = RTL_OSVERSIONINFOEXW.sizeof;
					if (pRtlGetVersion(&rovi) == 0) {
						major = rovi.dwMajorVersion;
						minor = rovi.dwMinorVersion;
						build = rovi.dwBuildNumber;
					}
				}
			}

			HKEY hKeyWin;
			if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", 0, KEY_READ, &hKeyWin) == ERROR_SUCCESS) {
				char[256] buf;
				DWORD sz = buf.sizeof;
				DWORD typ;
				if (RegQueryValueExA(hKeyWin, "ProductName", null, &typ, cast(ubyte*)buf.ptr, &sz) == ERROR_SUCCESS) {
					prodName = buf[0 .. sz].fromStringz.idup;
				}
				RegCloseKey(hKeyWin);
			}

			if (major != 0) {
				info.osVersion = format("%d.%d.%d", major, minor, build);
			} else {
				info.osVersion = "Unknown";
			}

			if (prodName.length > 0) {
				if (major == 10 && build >= 22000 && prodName.startsWith("Windows 10")) {
					import std.array : replace;
					info.osName = prodName.replace("Windows 10", "Windows 11");
				} else {
					info.osName = prodName;
				}
			} else if (major == 10 && build >= 22000) {
				info.osName = "Windows 11";
			} else if (major == 10) {
				info.osName = "Windows 10";
			} else if (major == 6 && minor == 3) {
				info.osName = "Windows 8.1";
			} else if (major == 6 && minor == 2) {
				info.osName = "Windows 8";
			} else if (major == 6 && minor == 1) {
				info.osName = "Windows 7";
			} else {
				info.osName = format("Windows %d.%d", major, minor);
			}

			SYSTEM_INFO si;
			GetSystemInfo(&si);
			info.cpuThreads = si.dwNumberOfProcessors;
			info.cpuCores   = info.cpuThreads;

			HKEY hKey;
			if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
					"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
					0, KEY_READ, &hKey) == ERROR_SUCCESS)
			{
				char[256] buf; DWORD sz = buf.sizeof; DWORD typ;
				if (RegQueryValueExA(hKey, "ProcessorNameString", null, &typ,
						cast(ubyte*)buf.ptr, &sz) == ERROR_SUCCESS)
					info.cpuModel = buf[0 .. sz].fromStringz.idup;
				RegCloseKey(hKey);
			}
			if (info.cpuModel.length == 0) info.cpuModel = "Unknown CPU";

			MEMORYSTATUSEX ms;
			ms.dwLength = MEMORYSTATUSEX.sizeof;
			if (GlobalMemoryStatusEx(&ms)) {
				info.totalRam     = ms.ullTotalPhys;
				info.availableRam = ms.ullAvailPhys;
			}
		} else version (linux) {
			import std.file   : readText, exists;
			import std.string : splitLines, strip, startsWith, split;
			import std.conv   : to;

			info.osName = "Linux";
			if (exists("/etc/os-release")) {
				foreach (line; readText("/etc/os-release").splitLines()) {
					if (line.startsWith("PRETTY_NAME=")) {
						info.osName = line["PRETTY_NAME=".length .. $].strip('"').idup;
						break;
					}
				}
			}
			if (exists("/proc/cpuinfo")) {
				foreach (line; readText("/proc/cpuinfo").splitLines()) {
					if (line.startsWith("model name") && info.cpuModel.length == 0) {
						auto idx = line.indexOf(':');
						if (idx >= 0) info.cpuModel = line[idx+1..$].strip.idup;
					}
					if (line.startsWith("processor")) info.cpuThreads++;
				}
				if (info.cpuCores == 0) info.cpuCores = info.cpuThreads;
			}
			if (info.cpuModel.length == 0) info.cpuModel = "Unknown CPU";
			if (exists("/proc/meminfo")) {
				foreach (line; readText("/proc/meminfo").splitLines()) {
					auto parts = line.split();
					if (line.startsWith("MemTotal:") && parts.length >= 2)
						info.totalRam = parts[1].to!ulong * 1024;
					if (line.startsWith("MemAvailable:") && parts.length >= 2)
						info.availableRam = parts[1].to!ulong * 1024;
				}
			}
		} else version (OSX) {
			info.osName   = "macOS";
			info.cpuModel = "Apple CPU";
		} else {
			info.osName   = "Unknown OS";
			info.cpuModel = "Unknown CPU";
		}

		return info;
	}
}

class RaylibSound : ISound {
	import raylib : Sound, PlaySound, StopSound, SetSoundVolume, IsSoundPlaying, UnloadSound;
	Sound rlSound;

	this(Sound s) {
		this.rlSound = s;
	}

	~this() {
		UnloadSound(rlSound);
	}

	override void play() { PlaySound(rlSound); }
	override void stop() { StopSound(rlSound); }
	override void setVolume(float volume) { SetSoundVolume(rlSound, volume); }
	override bool isPlaying() { return IsSoundPlaying(rlSound); }
	override void update() {}
}

class RaylibMusic : ISound {
	import raylib : Music, PlayMusicStream, StopMusicStream, SetMusicVolume, IsMusicStreamPlaying, UpdateMusicStream, UnloadMusicStream;
	Music rlMusic;

	this(Music m) {
		this.rlMusic = m;
	}

	~this() {
		UnloadMusicStream(rlMusic);
	}

	override void play() { PlayMusicStream(rlMusic); }
	override void stop() { StopMusicStream(rlMusic); }
	override void setVolume(float volume) { SetMusicVolume(rlMusic, volume); }
	override bool isPlaying() { return IsMusicStreamPlaying(rlMusic); }
	override void update() { UpdateMusicStream(rlMusic); }
}

class RaylibAudioDevice : IAudioDevice {
	import raylib : InitAudioDevice, CloseAudioDevice, IsAudioDeviceReady, LoadSound, SetMasterVolume;

	override void init() {
		import raylib : SetTraceLogLevel, TraceLogLevel;
		SetTraceLogLevel(TraceLogLevel.LOG_ALL);
		if (!IsAudioDeviceReady()) {
			InitAudioDevice();
		}
	}

	override void cleanup() {
		if (IsAudioDeviceReady()) {
			CloseAudioDevice();
		}
	}

	override Outcome!ISound loadSound(string path) {
		import std.string : toStringz;
		auto s = LoadSound(path.toStringz);
		// Note: checking if sound is loaded correctly in raylib-d is tricky as Sound struct has ptrs.
		// Usually if it fails, it returns empty data.
		return success!ISound(new RaylibSound(s));
	}

	override Outcome!ISound loadMusic(string path) {
		import raylib : LoadMusicStream, IsAudioDeviceReady;
		import std.stdio : writeln;
		writeln("[AUDIO] Loading music stream (Raylib): ", path);
		if (!IsAudioDeviceReady()) {
			writeln("[AUDIO] Error: Audio device is not ready (Raylib) when loading music!");
			return failure!ISound(Result.error, "Audio device is not ready");
		}
		auto m = LoadMusicStream(path.toStringz);
		if (m.frameCount == 0) {
			writeln("[AUDIO] Failed to load music stream (frameCount == 0): ", path);
			return failure!ISound(Result.error, "Failed to load music (frameCount == 0)");
		}
		writeln("[AUDIO] Music stream loaded: ", m.frameCount, " frames");
		return success!ISound(new RaylibMusic(m));
	}

	override void setMasterVolume(float volume) {
		SetMasterVolume(volume);
	}
}
