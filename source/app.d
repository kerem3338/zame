import zame;
import std;

Surface surface;
uint[] tempBuffer;

Instance instance;

version(Windows) {
	import core.sys.windows.windows;
	import core.runtime;
	import core.sys.windows.windows;
	import core.sys.windows.winuser;
	import core.sys.windows.windows;
	import core.sys.windows.winuser;
	import std.string;
	import std.utf : toUTF16z;
}

extern(Windows)
LRESULT wndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
	switch(msg)
	{
		

		case WM_KEYDOWN:
		case WM_SYSKEYDOWN:
		{
			ushort vk = cast(ushort)wParam;
			ushort scanCode = cast(ushort)((lParam >> 16) & 0xFF);

			
			ubyte[256] keyboardState;
			GetKeyboardState(&keyboardState[0]);

			wchar[5] buffer;
			int n = ToUnicode(vk, scanCode, &keyboardState[0], &buffer[0], buffer.length, 0);

			if (n > 0) {
				foreach(c; buffer[0..n]) {
					Event e;
					e.type = EventType.keyPressed;
					e.key = KeyEvent(c);
					instance.pushEvent(e);
				}
			}
			return 0;
		}

		case WM_KEYUP:
		case WM_SYSKEYUP:
		{
			ushort vk = cast(ushort)wParam;
			ushort scanCode = cast(ushort)((lParam >> 16) & 0xFF);

			ubyte[256] keyboardState;
			GetKeyboardState(&keyboardState[0]);

			wchar[5] buffer;
			int n = ToUnicode(vk, scanCode, &keyboardState[0], &buffer[0], buffer.length, 0);

			if (n > 0) {
				foreach(c; buffer[0..n]) {
					Event e;
					e.type = EventType.keyReleased;
					e.key = KeyEvent(c);
					instance.pushEvent(e);
				}
			}
			return 0;
		}

		


		case WM_MOUSEMOVE:
		{
			int mx = cast(int)LOWORD(lParam);
			int my = cast(int)HIWORD(lParam);

			RECT rect;
			GetClientRect(hwnd, &rect);
			int winW = rect.right - rect.left;
			int winH = rect.bottom - rect.top;

			int sx = mx * surface.width  / winW;
			int sy = my * surface.height / winH;

			if (sx < 0) sx = 0;
			if (sy < 0) sy = 0;
			if (sx >= surface.width)  sx = surface.width - 1;
			if (sy >= surface.height) sy = surface.height - 1;

			Event eMouse;
			eMouse.type = EventType.mouseMoved;
			eMouse.mouseMoved = MouseMoveEvent(sx, sy);
			instance.pushEvent(eMouse);




			InvalidateRect(hwnd, null, FALSE);
			return 0;
		}


		case WM_PAINT:
			PAINTSTRUCT ps;
			HDC hdc = BeginPaint(hwnd, &ps);

			foreach (i; 0 .. tempBuffer.length)
			{
				auto c = surface.rawData[i];
				tempBuffer[i] =
					(c.b) |
					(c.g << 8) |
					(c.r << 16) |
					(c.a << 24);
			}

			BITMAPINFO bmi = void;
			bmi.bmiHeader.biSize = BITMAPINFOHEADER.sizeof;
			bmi.bmiHeader.biWidth = surface.width;
			bmi.bmiHeader.biHeight = -cast(int)surface.height;
			bmi.bmiHeader.biPlanes = 1;
			bmi.bmiHeader.biBitCount = 32;
			bmi.bmiHeader.biCompression = BI_RGB;

			RECT rect;
			GetClientRect(hwnd, &rect);
			int winW = rect.right - rect.left;
			int winH = rect.bottom - rect.top;

			StretchDIBits(
				hdc,
				0, 0, winW, winH,
				0, 0, surface.width, surface.height,
				tempBuffer.ptr,
				&bmi,
				DIB_RGB_COLORS,
				SRCCOPY
			);

			EndPaint(hwnd, &ps);
			return 0;

		case WM_DESTROY:
			PostQuitMessage(0);
			return 0;

		default:
			break;
	}

	return DefWindowProcW(hwnd, msg, wParam, lParam);
}

int main()
{
	instance = new Instance(new Window(640,640));
	
	surface = new Surface(640,640);

	foreach (y; 0 .. surface.height)
	foreach (x; 0 .. surface.width) {
		surface.setPixel(Point(x, y), Color(x & 255, y & 255, (x+y) & 255));
	}
	
	HINSTANCE hInstance = GetModuleHandleW(null);

	auto className  = "DWinClass".toUTF16z;
	auto windowName = instance.window.title.toUTF16z;

	WNDCLASSW wc;
	wc.style       = CS_HREDRAW | CS_VREDRAW;
	wc.lpfnWndProc =  cast(WNDPROC)&wndProc;
	wc.hInstance   = hInstance;
	wc.hCursor     = LoadCursorW(null, IDC_ARROW);
	wc.lpszClassName = className;

	RegisterClassW(&wc);
	tempBuffer = new uint[surface.width * surface.height];
	HWND hwnd = CreateWindowExW(
		0,
		className,
		windowName,
		WS_OVERLAPPEDWINDOW,
		CW_USEDEFAULT, CW_USEDEFAULT,
		640, 800,
		null, null,
		hInstance,
		null
	);

	ShowWindow(hwnd, SW_SHOW);
	UpdateWindow(hwnd);

	bool running = true;

	Surface zameLogo = new Surface(0,0);
	loadFromPng(zameLogo, "resources/images/zame.png");

	BitmapFont font = new BitmapFont("resources/fonts/t33.png", "resources/fonts/t33.font-info",2);
	Surface helloWorld = font.getText("Zame Engine", Color(0,0,0), 45);

	MSG msg;
	while (running)
	{
	    while (PeekMessageW(&msg, null, 0, 0, PM_REMOVE))
	    {
	        if (msg.message == WM_QUIT)
	        {
	            running = false;
	            break;
	        }

	        TranslateMessage(&msg);
	        DispatchMessageW(&msg);
	    }


	    auto events = instance.pollEvents();
	    foreach (e; events)
	    {
	        switch (e.type)
	        {
	            case EventType.keyPressed:
	                writefln("Key pressed: %c", e.key.key);
	                break;

	            case EventType.mouseMoved:
	                auto me = e.mouseMoved;
	                surface.setPixel(Point(me.x, me.y), Color(0,0,0));
	                break;

	            default:
	                break;
	        }
	    }

	    surface.fill(Color(255,255,255));
	    surface.blit(helloWorld, 0,0);
	    surface.blit(zameLogo, 0,0);
	    InvalidateRect(hwnd, null, FALSE);
	    Sleep(1);
	}


	return 0;
}
