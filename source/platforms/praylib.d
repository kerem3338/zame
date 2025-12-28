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

class RaylibPlatform : IPlatform {
	Surface surfaceRef;
	Instance instanceRef;
	Window windowRef;

	Image image;
	Texture2D texture;

	bool initialized = false;
	bool shouldQuit = false;

	override string platformName() {
		return "Raylib";
	}

	override int createWindow(Window window) {
		windowRef = window;
		surfaceRef = window.surface;

		InitWindow(window.width, window.height, window.title.ptr);
		SetExitKey(KeyboardKey.KEY_NULL);

		if (!IsWindowReady())
			return -1;

		image = GenImageColor(
			cast(int)surfaceRef.width,
			cast(int)surfaceRef.height,
			RLColor(0, 0, 0, 0)
		);

		texture = LoadTextureFromImage(image);
		initialized = true;


		instanceRef.logger.info("Window created successfully");
		return 0;
	}

	void setWindowTitle(string title) {
		SetWindowTitle(title.ptr);
	}

	override void setInstance(Instance inst) {
		this.instanceRef = inst;
	}

	void setTargetFps(uint fps) {
		SetTargetFPS(fps);
	}

	void handleKeyboard() {
		if (instanceRef is null)
			return;

		int rayKey = GetKeyPressed();
		while (rayKey != 0) {
			KeyEvent ke;
			ke.code = toKeyCode(rayKey);
			ke.mods = getModifiers();
			ke.pressed = true;
			instanceRef.pushEvent(Event(EventType.keyPressed, ke));

			rayKey = GetKeyPressed();
		}

		int charCode = GetCharPressed();
		while (charCode != 0) {
			TextInputEvent te;
			te.character = cast(dchar)charCode;
			
			Event e;
			e.type = EventType.textInput;
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
			e.mouseMoved = MouseMoveEvent(sx, sy);
			instanceRef.pushEvent(e);
		}
	}

	void updateSurfaceToTexture() {
		if (!initialized || surfaceRef is null)
			return;

		ubyte* data = cast(ubyte*)image.data;

		foreach (i; 0 .. surfaceRef.rawData.length) {
			auto c = surfaceRef.rawData[i]; // zame.Color
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
		if (initialized) {
			UnloadTexture(texture);
			UnloadImage(image);
			initialized = false;
		}

		CloseWindow();
	}

	override bool isRunning() {
		return !shouldQuit;
	}
}
