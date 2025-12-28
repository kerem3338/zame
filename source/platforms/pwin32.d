module platforms.pwin32;

import zame;
import std;

version(Windows) {
    import core.sys.windows.windows;
    import core.runtime;
    import core.sys.windows.winuser;
    import std.string;
    import std.utf : toUTF16z;

    class Win32Platform : IPlatform {
        HWND hwnd;
        uint[] tempBuffer;
        Surface surfaceRef;
        Instance instanceRef;
        HDC hdc;
        Window windowRef;
        bool shouldQuit = false;

        override string platformName() {
            return "Win32";
        }
        
        override int createWindow(Window window) {
            this.windowRef = window;
            this.surfaceRef = window.surface;
            
            HINSTANCE hInstance = GetModuleHandleW(null);

            auto className = "DWinClass".toUTF16z;
            auto windowName = window.title.toUTF16z;

            WNDCLASSW wc;
            wc.style = CS_HREDRAW | CS_VREDRAW;
            wc.lpfnWndProc = cast(WNDPROC)&wndProc;
            wc.cbClsExtra = 0;
            wc.cbWndExtra = 0;
            wc.hInstance = hInstance;
            wc.hIcon = null;
            wc.hCursor = LoadCursorW(null, IDC_ARROW);
            wc.hbrBackground = cast(HBRUSH)GetStockObject(BLACK_BRUSH);
            wc.lpszMenuName = null;
            wc.lpszClassName = className;

            if (RegisterClassW(&wc) == 0) {
                return -1;
            }

            tempBuffer = new uint[surfaceRef.width * surfaceRef.height];

            auto platformPtr = cast(void*)this;
            
            hwnd = CreateWindowExW(
                0,
                className,
                windowName,
                WS_OVERLAPPEDWINDOW,
                CW_USEDEFAULT, CW_USEDEFAULT,
                window.width, window.height,
                null, null,
                hInstance,
                platformPtr
            );

            if (hwnd is null) {
                return -2;
            }

            ShowWindow(hwnd, SW_SHOW);
            UpdateWindow(hwnd);

            hdc = GetDC(hwnd);
            instanceRef.logger.info("Window created successfully");
            return 0;
        }

        void setWindowTitle(string title) {
            SetWindowText(hwnd, title.toUTF16z);
        }
        
        override void setInstance(Instance inst) {
            this.instanceRef = inst;
        }

        override void processMessages() {
            MSG msg;
            // NON-BLOCKING: PM_REMOVE yerine PM_NOREMOVE veya PM_NOYIELD kullan
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
            if (hwnd !is null) {
                InvalidateRect(hwnd, null, FALSE);
            }
        }

        override void cleanup() {
            if (hdc !is null) {
                ReleaseDC(hwnd, hdc);
                hdc = null;
            }
            
            if (hwnd !is null) {
                DestroyWindow(hwnd);
                hwnd = null;
            }
            
            auto className = "DWinClass".toUTF16z;
            UnregisterClassW(className, GetModuleHandleW(null));
        }

        override bool isRunning() {
            return !shouldQuit && hwnd !is null;
        }

        void handlePaint() {
            if (surfaceRef is null || tempBuffer.length == 0) return;
            
            PAINTSTRUCT ps;
            HDC hdcPaint = BeginPaint(hwnd, &ps);

            // Update temp buffer with surface data
            foreach (i; 0 .. tempBuffer.length) {
                auto c = surfaceRef.rawData[i];
                tempBuffer[i] =
                    (c.b) |
                    (c.g << 8) |
                    (c.r << 16) |
                    (c.a << 24);
            }

            BITMAPINFO bmi = void;
            bmi.bmiHeader.biSize = BITMAPINFOHEADER.sizeof;
            bmi.bmiHeader.biWidth = surfaceRef.width;
            bmi.bmiHeader.biHeight = -cast(int)surfaceRef.height;
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
                0, 0, surfaceRef.width, surfaceRef.height,
                tempBuffer.ptr,
                &bmi,
                DIB_RGB_COLORS,
                SRCCOPY
            );

            EndPaint(hwnd, &ps);
        }

        void handleMouseMove(int mx, int my) {
            if (surfaceRef is null || instanceRef is null) return;
            
            RECT rect;
            GetClientRect(hwnd, &rect);
            int winW = rect.right - rect.left;
            int winH = rect.bottom - rect.top;

            int sx = mx * surfaceRef.width / winW;
            int sy = my * surfaceRef.height / winH;

            if (sx < 0) sx = 0;
            if (sy < 0) sy = 0;
            if (sx >= surfaceRef.width) sx = surfaceRef.width - 1;
            if (sy >= surfaceRef.height) sy = surfaceRef.height - 1;

            Event eMouse;
            eMouse.type = EventType.mouseMoved;
            eMouse.mouseMoved = MouseMoveEvent(sx, sy);
            instanceRef.pushEvent(eMouse);
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

        void handleKeyEvent(UINT msg, WPARAM wParam, LPARAM lParam) {
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
            e.key = ke;
            instanceRef.pushEvent(e);

            if (eventType == EventType.keyPressed) {
                ushort scanCode = cast(ushort)((lParam >> 16) & 0xFF);
                ubyte[256] keyboardState;
                GetKeyboardState(&keyboardState[0]);

                wchar[5] buffer;
                int n = ToUnicode(vk, scanCode, &keyboardState[0], &buffer[0], buffer.length, 0);

                if (n > 0) {
                    foreach (c; buffer[0..n]) {
                        TextInputEvent te;
                        te.character = cast(dchar)c;
                        
                        Event teEvent;
                        teEvent.type = EventType.textInput;
                        teEvent.textInput = te;
                        instanceRef.pushEvent(teEvent);
                    }
                }
            }
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
                platform.handleKeyEvent(msg, wParam, lParam);
                return 0;

            case WM_MOUSEMOVE:
                int mx = cast(int)LOWORD(lParam);
                int my = cast(int)HIWORD(lParam);
                platform.handleMouseMove(mx, my);
                return 0;

            case WM_PAINT:
                platform.handlePaint();
                return 0;

            case WM_CLOSE:
                DestroyWindow(hwnd);
                return 0;

            case WM_DESTROY:
                auto hwndPtr = cast(void*)hwnd;
                if (hwndPtr in platformMap) {
                    platformMap.remove(hwndPtr);
                }
                PostQuitMessage(0);
                return 0;

            default:
                break;
        }

        return DefWindowProcW(hwnd, msg, wParam, lParam);
    }
}