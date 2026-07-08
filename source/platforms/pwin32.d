module platforms.pwin32;

import zame;
import std;

version(Windows) {
	import core.sys.windows.windows;
	import core.runtime;
	import core.sys.windows.winuser;
	import core.stdc.string : strlen, memcpy;
	import std.string;
	import std.utf : toUTF16z;
	import raylib;
	pragma(lib, "winmm.lib");
	extern(Windows) uint timeBeginPeriod(uint);
	extern(Windows) uint timeEndPeriod(uint);

	class Win32Platform : IPlatform {
		struct WindowContext {
			HWND hwnd;
			HDC hdc;
			Window windowRef;
			uint[] tempBuffer;
			Surface surfaceRef;
		}

		WindowContext[HWND] contexts;
		HWND mainHwnd;
		Instance instanceRef;
		bool shouldQuit = false;

		override string platformName() {
			return PlatformName.win32;
		}

		override PlatformCapabilities capabilities() {
			return PlatformCapabilities(true);
		}
		
		override int createWindow(Window window) {
			HINSTANCE hInstance = GetModuleHandleW(null);

			auto className = "ZameEngineClass".toUTF16z;
			auto windowName = window.title.toUTF16z;

			WNDCLASSW wc;
			wc.style = CS_HREDRAW | CS_VREDRAW;
			wc.lpfnWndProc = cast(WNDPROC)&wndProc;
			wc.cbClsExtra = 0;
			wc.cbWndExtra = 0;
			wc.hInstance = hInstance;
			
			if (window.iconPath !is null && window.iconPath.length > 0) {
				wc.hIcon = createHIconFromFile(window.iconPath);
			} 
			
			if (wc.hIcon is null) {
				wc.hIcon = LoadIconW(null, IDI_APPLICATION);
			}

			wc.hCursor = LoadCursorW(null, IDC_ARROW);
			wc.hbrBackground = cast(HBRUSH)GetStockObject(BLACK_BRUSH);
			wc.lpszMenuName = null;
			wc.lpszClassName = className;

			RegisterClassW(&wc);

			auto platformPtr = cast(void*)this;
			
			HWND parentHwnd = null;
			DWORD style = WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_CLIPSIBLINGS;

			if (!window.settings.get("window_resizable", true)) {
				style &= ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
			}

			if (window.parent !is null) {
				foreach (hwnd, ctx; contexts) {
					if (ctx.windowRef is window.parent) {
						parentHwnd = cast(HWND)hwnd;
						break;
					}
				}
				if (parentHwnd !is null) {
					style = WS_CHILD | WS_VISIBLE | WS_BORDER | WS_CAPTION | WS_SYSMENU | WS_CLIPSIBLINGS;
				}
			}

			RECT windowRect = RECT(0, 0, window.width, window.height);
			AdjustWindowRectEx(&windowRect, style, FALSE, 0);

			HWND hwnd = CreateWindowExW(
				0,
				className,
				windowName,
				style,
				CW_USEDEFAULT, CW_USEDEFAULT,
				windowRect.right - windowRect.left, windowRect.bottom - windowRect.top,
				parentHwnd, null,
				hInstance,
				platformPtr
			);

			if (hwnd is null) {
				return -2;
			}

			if (mainHwnd is null) mainHwnd = hwnd;

			WindowContext ctx;
			ctx.hwnd = hwnd;
			ctx.hdc = GetDC(hwnd);
			ctx.windowRef = window;
			ctx.surfaceRef = window.surface;
			contexts[hwnd] = ctx;

			ShowWindow(hwnd, SW_SHOW);
			UpdateWindow(hwnd);

			timeBeginPeriod(1);

			// Initialize audio device if not already
			if (this.audioDevice is null) {
				this.audioDevice = new Win32RaylibAudioDevice();
			}
			(cast(Win32RaylibAudioDevice)this.audioDevice).realInit();

			instanceRef.logger.info("Window created successfully");
			return 0;
		}

		override bool updateWindowSettings() {
			LONG_PTR style = GetWindowLongPtr(mainHwnd, GWL_STYLE);

			// check for resizing
			if (contexts[mainHwnd].windowRef.settings.get("window_resizable", true)) {
				style |= (WS_THICKFRAME | WS_MAXIMIZEBOX);
			} else {
				style &= ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
			}

			SetWindowLongPtr(mainHwnd, GWL_STYLE, style);
			SetWindowPos(mainHwnd, NULL, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
			
			return true;
		}

		void setWindowTitle(Window window, string title) {
			foreach (hwnd, ctx; contexts) {
				if (ctx.windowRef is window) {
					SetWindowText(cast(HWND)hwnd, title.toUTF16z);
					break;
				}
			}
		}
		
		override void setInstance(Instance inst) {
			this.instanceRef = inst;
		}

		override void setTargetFps(uint fps) {
			this.targetFps = fps;
		}

		override uint getTargetFps() {
			return this.targetFps;
		}

		override void setIcon(string path) {
			if (mainHwnd is null) return;
			HICON hIcon = createHIconFromFile(path);
			if (hIcon !is null) {
				SendMessageW(mainHwnd, WM_SETICON, ICON_BIG, cast(LPARAM)hIcon);
				SendMessageW(mainHwnd, WM_SETICON, ICON_SMALL, cast(LPARAM)hIcon);
			}
		}

		void setWindowSize(Window window, int width, int height) {
			foreach(hwnd, ctx; contexts) {
				if (ctx.windowRef is window) {
					RECT rect = RECT(0, 0, width, height);
					DWORD style = GetWindowLongW(cast(HWND)hwnd, GWL_STYLE);
					AdjustWindowRect(&rect, style, FALSE);
					int w = rect.right - rect.left;
					int h = rect.bottom - rect.top;
					SetWindowPos(cast(HWND)hwnd, null, 0, 0, w, h, SWP_NOMOVE | SWP_NOZORDER);
					break;
				}
			}
		}

		private HICON createHIconFromFile(string path) {
			import zame.core.graphics : surfaceFromImage, Surface;
			
			auto res = surfaceFromImage(path);
			if (res.ok) {
				return createHICON(res.value);
			}

			return cast(HICON)LoadImageW(null, path.toUTF16z, IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE);
		}

		private HICON createHICON(zame.core.graphics.Surface surface) {
			if (surface is null) return null;

			int w = surface.width;
			int h = surface.height;

			BITMAPV5HEADER bi;
			bi.bV5Size = BITMAPV5HEADER.sizeof;
			bi.bV5Width = w;
			bi.bV5Height = -h;
			bi.bV5Planes = 1;
			bi.bV5BitCount = 32;
			bi.bV5Compression = BI_BITFIELDS;
			bi.bV5RedMask   = 0x00FF0000;
			bi.bV5GreenMask = 0x0000FF00;
			bi.bV5BlueMask  = 0x000000FF;
			bi.bV5AlphaMask = 0xFF000000;

			void* bits;
			HDC screenDC = GetDC(null);
			HBITMAP hBitmap = CreateDIBSection(screenDC, cast(BITMAPINFO*)&bi, DIB_RGB_COLORS, &bits, null, 0);
			ReleaseDC(null, screenDC);

			if (hBitmap is null) return null;

			uint* dst = cast(uint*)bits;
			auto src = surface.rawData;
			foreach (i; 0 .. w * h) {
				auto c = src[i];
				// BGRA
				dst[i] = (c.b) | (c.g << 8) | (c.r << 16) | (c.a << 24);
			}

			HBITMAP hMonoBitmap = CreateBitmap(w, h, 1, 1, null);

			ICONINFO ii;
			ii.fIcon = TRUE;
			ii.xHotspot = 0;
			ii.yHotspot = 0;
			ii.hbmMask = hMonoBitmap;
			ii.hbmColor = hBitmap;

			HICON hIcon = CreateIconIndirect(&ii);

			DeleteObject(hBitmap);
			DeleteObject(hMonoBitmap);

			return hIcon;
		}

		uint targetFps = 60;

		override void processMessages() {
			MSG msg;
			// non-blocking: instead of PM_REMOVE use PM_NOREMOVE or PM_NOYIELD
			while (PeekMessageW(&msg, null, 0, 0, PM_REMOVE)) {
				if (msg.message == WM_QUIT) {
					shouldQuit = true;
					PostQuitMessage(0);
					return;
				}

				TranslateMessage(&msg);
				DispatchMessageW(&msg);
			}
		}
		
		void processMessagesNonBlocking() {
			MSG msg;
			while (PeekMessageW(&msg, null, 0, 0, PM_REMOVE | PM_NOYIELD)) {
				if (msg.message == WM_QUIT) {
					shouldQuit = true;
					return;
				}

				TranslateMessage(&msg);
				DispatchMessageW(&msg);
			}
		}

		override void invalidate() {
			foreach (hwnd, ctx; contexts) {
				InvalidateRect(cast(HWND)hwnd, null, FALSE);
			}
		}

		override void cleanup() {
			foreach (hwnd, ctx; contexts) {
				if (ctx.hdc !is null) {
					ReleaseDC(cast(HWND)hwnd, ctx.hdc);
				}
				DestroyWindow(cast(HWND)hwnd);
			}
			contexts.clear();
			mainHwnd = null;
			
			auto className = "ZameEngineClass".toUTF16z;
			UnregisterClassW(className, GetModuleHandleW(null));
			timeEndPeriod(1);

			if (audioDevice !is null) {
				audioDevice.cleanup();
			}
		}

		override bool isRunning() {
			return !shouldQuit && mainHwnd !is null;
		}

		override void exit() {
			shouldQuit = true;
		}

		void handlePaint(HWND hwnd) {
			auto pCtx = hwnd in contexts;
			if (pCtx is null) return;
			auto ctx = *pCtx;

			if (ctx.surfaceRef is null) return;
			
			PAINTSTRUCT ps;
			HDC hdcPaint = BeginPaint(hwnd, &ps);

			BITMAPINFO bmi;
			bmi.bmiHeader.biSize = BITMAPINFOHEADER.sizeof;
			bmi.bmiHeader.biWidth = ctx.surfaceRef.width;
			bmi.bmiHeader.biHeight = -cast(int)ctx.surfaceRef.height;
			bmi.bmiHeader.biPlanes = 1;
			bmi.bmiHeader.biBitCount = 32;
			bmi.bmiHeader.biCompression = BI_RGB;

			RECT rect;
			GetClientRect(hwnd, &rect);
			int winW = rect.right - rect.left;
			int winH = rect.bottom - rect.top;

			StretchDIBits(
				hdcPaint,
				0, 0, winW, winH,
				0, 0, ctx.surfaceRef.width, ctx.surfaceRef.height,
				ctx.surfaceRef.rawData.ptr,
				&bmi,
				DIB_RGB_COLORS,
				SRCCOPY
			);

			EndPaint(hwnd, &ps);
		}

		void handleMouseMove(HWND hwnd, int mx, int my) {
			auto pCtx = hwnd in contexts;
			if (pCtx is null || instanceRef is null) return;
			auto ctx = *pCtx;
			
			RECT rect;
			GetClientRect(hwnd, &rect);
			int winW = rect.right - rect.left;
			int winH = rect.bottom - rect.top;

			int sx = mx * ctx.surfaceRef.width / winW;
			int sy = my * ctx.surfaceRef.height / winH;

			if (sx < 0) sx = 0;
			if (sy < 0) sy = 0;
			if (sx >= ctx.surfaceRef.width) sx = ctx.surfaceRef.width - 1;
			if (sy >= ctx.surfaceRef.height) sy = ctx.surfaceRef.height - 1;

			Event eMouse;
			eMouse.type = EventType.mouseMoved;
			eMouse.window = ctx.windowRef;
			eMouse.mouseMoved = MouseMoveEvent(sx, sy);
			instanceRef.pushEvent(eMouse);
		}

		void handleMouseButton(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
			auto pCtx = hwnd in contexts;
			if (pCtx is null || instanceRef is null) return;
			auto ctx = *pCtx;

			RECT rect;
			GetClientRect(hwnd, &rect);
			int winW = rect.right - rect.left;
			int winH = rect.bottom - rect.top;

			int mx = cast(int)LOWORD(lParam);
			int my = cast(int)HIWORD(lParam);
			int sx = mx * ctx.surfaceRef.width / winW;
			int sy = my * ctx.surfaceRef.height / winH;

			MouseEvent me;
			me.x = sx;
			me.y = sy;

			switch (msg) {
				case WM_LBUTTONDOWN:
				case WM_LBUTTONUP:
					me.button = MouseEvent.ButtonType.left;
					break;
				case WM_RBUTTONDOWN:
				case WM_RBUTTONUP:
					me.button = MouseEvent.ButtonType.right;
					break;
				case WM_MBUTTONDOWN:
				case WM_MBUTTONUP:
					me.button = MouseEvent.ButtonType.middle;
					break;
				default: break;
			}

			Event e;
			e.type = (msg == WM_LBUTTONDOWN || msg == WM_RBUTTONDOWN || msg == WM_MBUTTONDOWN)
				? EventType.mouseButtonPressed
				: EventType.mouseButtonReleased;
			e.window = ctx.windowRef;
			e.mouse = me;
			instanceRef.pushEvent(e);
		}

		void handleMouseWheel(HWND hwnd, WPARAM wParam, LPARAM lParam) {
			if (instanceRef is null) return;

			short delta = cast(short)HIWORD(cast(DWORD)wParam);
			
			Event e;
			e.type = EventType.mouseWheel;
			auto pCtx = hwnd in contexts;
			if (pCtx !is null) e.window = pCtx.windowRef;
			e.mouseWheel.delta = cast(int)delta;
			instanceRef.pushEvent(e);
		}

		void handleResize(HWND hwnd, int width, int height) {
			auto pCtx = hwnd in contexts;
			if (pCtx is null || instanceRef is null) return;
			auto ctx = *pCtx;
			
			// Resize internal logic
			ctx.windowRef.onResize(width, height);
			ctx.surfaceRef = ctx.windowRef.surface;
			contexts[hwnd] = ctx; // Update struct copy? D structs... context is value type?
			// Actually contexts[hwnd] returns ref or copy? It's an AA.
			// But we need to update it back if we modified it
			contexts[hwnd].surfaceRef = ctx.windowRef.surface;

			Event e;
			e.type = EventType.resized;
			e.window = ctx.windowRef;
			e.resize = WindowResizeEvent(width, height);
			instanceRef.pushEvent(e);
		}

		KeyCode toKeyCode(ushort vk) {
			switch (vk) {
				case 0x41: .. case 0x5A: return cast(KeyCode)(KeyCode.A + (vk - 0x41));
				case 0x30: .. case 0x39: return cast(KeyCode)(KeyCode.Num0 + (vk - 0x30));
				case VK_F1: .. case VK_F12: return cast(KeyCode)(KeyCode.F1 + (vk - VK_F1));
				
				case VK_ESCAPE: return KeyCode.Escape;
				case VK_TAB: return KeyCode.Tab;
				case VK_CAPITAL: return KeyCode.CapsLock;
				case VK_SHIFT: return KeyCode.ShiftLeft;
				case VK_LSHIFT: return KeyCode.ShiftLeft;
				case VK_RSHIFT: return KeyCode.ShiftRight;
				case VK_CONTROL: return KeyCode.CtrlLeft;
				case VK_LCONTROL: return KeyCode.CtrlLeft;
				case VK_RCONTROL: return KeyCode.CtrlRight;
				case VK_MENU: return KeyCode.AltLeft;
				case VK_LMENU: return KeyCode.AltLeft;
				case VK_RMENU: return KeyCode.AltRight;
				case VK_LWIN: return KeyCode.SuperLeft;
				case VK_RWIN: return KeyCode.SuperRight;
				case VK_RETURN: return KeyCode.Enter;
				case VK_BACK: return KeyCode.Backspace;
				case VK_SPACE: return KeyCode.Space;
				
				case VK_UP: return KeyCode.ArrowUp;
				case VK_DOWN: return KeyCode.ArrowDown;
				case VK_LEFT: return KeyCode.ArrowLeft;
				case VK_RIGHT: return KeyCode.ArrowRight;
				
				case VK_INSERT: return KeyCode.Insert;
				case VK_DELETE: return KeyCode.Delete;
				case VK_HOME: return KeyCode.Home;
				case VK_END: return KeyCode.End;
				case VK_PRIOR: return KeyCode.PageUp;
				case VK_NEXT: return KeyCode.PageDown;
				
				default: return KeyCode.Unknown;
			}
		}

		Modifiers getModifiers() {
			Modifiers mods = Modifiers.None;
			if (GetKeyState(VK_SHIFT) & 0x8000) mods |= Modifiers.Shift;
			if (GetKeyState(VK_CONTROL) & 0x8000) mods |= Modifiers.Ctrl;
			if (GetKeyState(VK_MENU) & 0x8000) mods |= Modifiers.Alt;
			if ((GetKeyState(VK_LWIN) & 0x8000) || (GetKeyState(VK_RWIN) & 0x8000)) mods |= Modifiers.Super;
			return mods;
		}

		void handleKeyEvent(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
			if (instanceRef is null) return;
			
			ushort vk = cast(ushort)wParam;
			
			EventType eventType = (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN) 
				? EventType.keyPressed 
				: EventType.keyReleased;

			KeyEvent ke;
			ke.code = toKeyCode(vk);
			ke.mods = getModifiers();
			ke.pressed = (eventType == EventType.keyPressed);

			Event e;
			e.type = eventType;
			auto pCtx = hwnd in contexts;
			if (pCtx !is null) e.window = pCtx.windowRef;
			e.key = ke;
			instanceRef.pushEvent(e);

			if (eventType == EventType.keyPressed) {
				ushort scanCode = cast(ushort)((lParam >> 16) & 0xFF);
				ubyte[256] keyboardState;
				GetKeyboardState(&keyboardState[0]);

				wchar[5] buffer;
				int n = ToUnicode(vk, scanCode, &keyboardState[0], &buffer[0], buffer.length, 0);

				if (n > 0) {
					import std.utf : toUTF32;
					foreach (dchar c; buffer[0..n].toUTF32) {
						if (c >= 32) { // filter out non-printable control chars example: \b, \r, \n
							TextInputEvent te;
							te.character = c;
							
							Event teEvent;
							teEvent.type = EventType.textInput;
							if (pCtx !is null) teEvent.window = pCtx.windowRef;
							teEvent.textInput = te;
							instanceRef.pushEvent(teEvent);
						}
					}
				}
			}
		}

		override IAudioDevice getAudioDevice() {
			if (audioDevice is null) audioDevice = new Win32RaylibAudioDevice();
			return audioDevice;
		}

		override string getClipboard() {
			if (!OpenClipboard(null)) return "";
			HANDLE hData = GetClipboardData(CF_TEXT);
			if (hData is null) {
				CloseClipboard();
				return "";
			}
			char* ptr = cast(char*)GlobalLock(hData);
			string res = cast(string)ptr[0 .. strlen(ptr)].idup;
			GlobalUnlock(hData);
			CloseClipboard();
			return res;
		}

		override void setClipboard(string text) {
			if (!OpenClipboard(null)) return;
			EmptyClipboard();
			HGLOBAL hGlob = GlobalAlloc(GMEM_MOVEABLE, text.length + 1);
			if (hGlob !is null) {
				char* ptr = cast(char*)GlobalLock(hGlob);
				memcpy(ptr, text.ptr, text.length);
				ptr[text.length] = 0;
				GlobalUnlock(hGlob);
				SetClipboardData(CF_TEXT, hGlob);
			}
			CloseClipboard();
		}

		override void showMouse(bool visible) {
			ShowCursor(visible ? TRUE : FALSE);
		}

		IAudioDevice audioDevice;
	}

	class Win32RaylibSound : ISound {
		import raylib : Sound, PlaySound, StopSound, SetSoundVolume, IsSoundPlaying, UnloadSound;
		Sound rlSound;

		this(Sound s) {
			this.rlSound = s;
		}

		~this() {
			UnloadSound(rlSound);
		}

		override void play() { 
			PlaySound(rlSound); 
		}
		override void stop() { StopSound(rlSound); }
		override void setVolume(float volume) { SetSoundVolume(rlSound, volume); }
		override bool isPlaying() { return IsSoundPlaying(rlSound); }
		override void update() {}
	}

	class Win32RaylibMusic : ISound {
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

	class Win32RaylibAudioDevice : IAudioDevice {
		import raylib : InitAudioDevice, CloseAudioDevice, IsAudioDeviceReady, LoadSound, SetMasterVolume;

		override void init() {
			// Do nothing here, wait for createWindow to ensure window is ready
			import raylib : SetTraceLogLevel, TraceLogLevel;
			SetTraceLogLevel(TraceLogLevel.LOG_ALL);
		}

		void realInit() {
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
			auto s = LoadSound(path.toStringz);
			return success!ISound(new Win32RaylibSound(s));
		}

		override Outcome!ISound loadMusic(string path) {
			import raylib : LoadMusicStream, IsAudioDeviceReady;
			import std.stdio : writeln;
			writeln("[AUDIO] Loading music stream: ", path);
			if (!IsAudioDeviceReady()) {
				writeln("[AUDIO] Error: Audio device is not ready when loading music!");
				return failure!ISound(Result.error, "Audio device is not ready");
			}
			auto m = LoadMusicStream(path.toStringz);
			if (m.frameCount == 0) {
				writeln("[AUDIO] Failed to load music stream (frameCount == 0): ", path);
				return failure!ISound(Result.error, "Failed to load music (frameCount == 0)");
			}
			writeln("[AUDIO] Music stream loaded: ", m.frameCount, " frames");
			return success!ISound(new Win32RaylibMusic(m));
		}

		override void setMasterVolume(float volume) {
			SetMasterVolume(volume);
		}
	}

	private Win32Platform[void*] platformMap;

	extern(Windows)
	LRESULT wndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
		Win32Platform platform = null;
		
		if (msg == WM_CREATE) {
			auto createStruct = cast(LPCREATESTRUCTW)lParam;
			auto platformPtr = createStruct.lpCreateParams;
			platform = cast(Win32Platform)platformPtr;
			
			if (platform !is null) {
				platformMap[cast(void*)hwnd] = platform;
			}
		} else {
			platform = cast(void*)hwnd in platformMap ? platformMap[cast(void*)hwnd] : null;
		}
		
		if (platform is null) {
			return DefWindowProcW(hwnd, msg, wParam, lParam);
		}

		switch (msg) {
			case WM_KEYDOWN:
			case WM_SYSKEYDOWN:
			case WM_KEYUP:
			case WM_SYSKEYUP:
				platform.handleKeyEvent(hwnd, msg, wParam, lParam);
				return 0;

			case WM_MOUSEMOVE:
				int mx = cast(int)LOWORD(lParam);
				int my = cast(int)HIWORD(lParam);
				platform.handleMouseMove(hwnd, mx, my);
				return 0;

			case WM_LBUTTONDOWN:
			case WM_LBUTTONUP:
			case WM_RBUTTONDOWN:
			case WM_RBUTTONUP:
			case WM_MBUTTONDOWN:
			case WM_MBUTTONUP:
				platform.handleMouseButton(hwnd, msg, wParam, lParam);
				return 0;

			case WM_MOUSEWHEEL:
				platform.handleMouseWheel(hwnd, wParam, lParam);
				return 0;

			case WM_PAINT:
				platform.handlePaint(hwnd);
				return 0;

			case WM_SIZE:
				int width = cast(int)LOWORD(lParam);
				int height = cast(int)HIWORD(lParam);
				platform.handleResize(hwnd, width, height);
				return 0;

			case WM_ERASEBKGND:
				return 1;

			case WM_CLOSE:
				DestroyWindow(hwnd);
				return 0;

			case WM_DESTROY:
				auto hwndPtr = cast(void*)hwnd;
				if (hwndPtr in platformMap) {
					platformMap.remove(hwndPtr);
				}
				if (hwnd in platform.contexts) {
					platform.contexts.remove(hwnd);
				}
				if (hwnd == platform.mainHwnd) {
					platform.mainHwnd = null;
					platform.shouldQuit = true;
					PostQuitMessage(0);
				}
				return 0;

			default:
				break;
		}

		return DefWindowProcW(hwnd, msg, wParam, lParam);
	}
}