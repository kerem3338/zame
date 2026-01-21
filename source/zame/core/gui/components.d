module zame.core.gui.components;

import zame.core.graphics;
import zame.core.common;
import zame.core.platform;
import zame.core.font;
import std.conv;
import std.string : chop;
import std.algorithm : min, max, sort;
import zame.core.gui.gui_object;


class Button : GUIObject {
    dstring text;
    void delegate() onClick;
    bool hovered = false;
    bool pressed = false;
    int fontSize = 16;

    this(dstring text, void delegate() onClick = null) {
        super();
        this.text = text;
        this.onClick = onClick;
    }

    override void update(float dt) {
    }

    override bool handleInput(Event event) {
        if (event.type == EventType.mouseMoved) {
            hovered = bounds.contains(Point(event.mouseMoved.x, event.mouseMoved.y));
        } else if (event.type == EventType.mouseButtonPressed && event.mouse.button == MouseEvent.ButtonType.left) {
            if (bounds.contains(Point(event.mouse.x, event.mouse.y))) {
                pressed = true;
                return true;
            }
        } else if (event.type == EventType.mouseButtonReleased && event.mouse.button == MouseEvent.ButtonType.left) {
            if (pressed) {
                pressed = false;
                if (bounds.contains(Point(event.mouse.x, event.mouse.y))) {
                    if (onClick !is null) onClick();
                }
                return true;
            }
        }
        return false;
    }

    Font font;

    override void draw(Surface surface) {
        Color bgColor = pressed ? Color(100, 100, 100) : (hovered ? Color(80, 80, 80) : Color(60, 60, 60));
        Graphics.drawRect(surface, bgColor, bounds);
        Graphics.drawRect(surface, Colors.white, Rect(bounds.x, bounds.y, bounds.w, 1));
        Graphics.drawRect(surface, Colors.white, Rect(bounds.x, bounds.y + bounds.h - 1, bounds.w, 1));
        Graphics.drawRect(surface, Colors.white, Rect(bounds.x, bounds.y, 1, bounds.h));
        Graphics.drawRect(surface, Colors.white, Rect(bounds.x + bounds.w - 1, bounds.y, 1, bounds.h));

        if (font !is null && text.length > 0) {
            Surface textSurf = font.getText(to!string(text), Colors.white, fontSize);
            surface.blit(textSurf, bounds.x + (bounds.w - textSurf.width) / 2, bounds.y + (bounds.h - textSurf.height) / 2);
        }
    }
}

class GUIWindow : GUIObject {
    dstring title;
    GUIObject[] children;
    Color bgColor = Color(30, 30, 40, 240);
    Color borderColor = Color(150, 150, 150);
    bool dragging = false;
    Point dragOffset;
    Font font;

    this(dstring title, Rect bounds) {
        super();
        this.title = title;
        this.bounds = bounds;
    }

    void addChild(GUIObject obj) {
        children ~= obj;
        sortChildren();
    }

    void sortChildren() {
        children.sort!((a, b) => a.layer < b.layer);
    }

    override void update(float dt) {
        foreach (child; children) {
            if (child.enabled) child.update(dt);
        }
    }

    override bool handleInput(Event event) {
        for (int i = cast(int)children.length - 1; i >= 0; i--) {
            auto child = children[i];
            if (child.enabled && child.visible) {
                if (child.handleInput(event)) return true;
            }
        }

        int mx = -1, my = -1;
        if (event.type == EventType.mouseMoved) {
            mx = event.mouseMoved.x;
            my = event.mouseMoved.y;
        } else if (event.type == EventType.mouseButtonPressed || event.type == EventType.mouseButtonReleased) {
            mx = event.mouse.x;
            my = event.mouse.y;
        }

        if (event.type == EventType.mouseButtonPressed && event.mouse.button == MouseEvent.ButtonType.left) {
            Rect titleBar = Rect(bounds.x, bounds.y, bounds.w, 30);
            if (titleBar.contains(Point(mx, my))) {
                dragging = true;
                dragOffset = Point(mx - bounds.x, my - bounds.y);
                return true;
            }
        } else if (event.type == EventType.mouseButtonReleased && event.mouse.button == MouseEvent.ButtonType.left) {
            dragging = false;
        } else if (event.type == EventType.mouseMoved && dragging) {
            int oldX = bounds.x;
            int oldY = bounds.y;
            bounds.x = mx - dragOffset.x;
            bounds.y = my - dragOffset.y;
            
            int dx = bounds.x - oldX;
            int dy = bounds.y - oldY;
            foreach (child; children) {
                child.bounds.x += dx;
                child.bounds.y += dy;
            }
            return true;
        }

        if (mx != -1 && my != -1 && bounds.contains(Point(mx, my))) return true;
        return false;
    }

    override void draw(Surface surface) {
        Graphics.drawRect(surface, bgColor, bounds);
        Graphics.drawRect(surface, Color(50, 50, 70), Rect(bounds.x, bounds.y, bounds.w, 30));
        Graphics.drawRect(surface, borderColor, Rect(bounds.x, bounds.y, bounds.w, 1));
        Graphics.drawRect(surface, borderColor, Rect(bounds.x, bounds.y + bounds.h - 1, bounds.w, 1));
        Graphics.drawRect(surface, borderColor, Rect(bounds.x, bounds.y, 1, bounds.h));
        Graphics.drawRect(surface, borderColor, Rect(bounds.x + bounds.w - 1, bounds.y, 1, bounds.h));

        if (font !is null && title.length > 0) {
            Surface titleSurf = font.getText(to!string(title), Colors.white, 16);
            surface.blit(titleSurf, bounds.x + 10, bounds.y + (30 - titleSurf.height) / 2);
        }

        foreach (child; children) {
            if (child.visible) child.draw(surface);
        }
    }
}

class TextInput : GUIObject {
    dstring text = "";
    int cursorPos = 0;
    int selectionAnchor = 0;
    bool focused = false;
    int maxLength = 100;
    
    float cursorTimer = 0.0f;
    bool showCursor = true;
    float blinkRate = 0.5f; // half a second
    int scrollX = 0;

    Color textColor = Colors.white;
    Color focusColor = Colors.yellow;
    Color selectionColor = Color(0, 120, 215, 128);
    Color bgColor = Color(0, 0, 0, 150);
    Color borderColor = Color(100, 100, 100);

    Font font;

    override void update(float dt) {
        if (!focused) {
            showCursor = false;
            return;
        }

        cursorTimer += dt;
        if (cursorTimer >= blinkRate) {
            cursorTimer -= blinkRate;
            showCursor = !showCursor;
        }
    }

    private void resetCursorBlink() {
        cursorTimer = 0.0f;
        showCursor = true;
    }

    private void deleteSelection() {
        if (selectionAnchor == cursorPos) return;
        
        int start = min(selectionAnchor, cursorPos);
        int end = max(selectionAnchor, cursorPos);
        
        text = text[0 .. start] ~ text[end .. $];
        cursorPos = start;
        selectionAnchor = start;
    }

    override bool handleInput(Event event) {
        if (event.type == EventType.mouseButtonPressed) {
            focused = bounds.contains(Point(event.mouse.x, event.mouse.y));
            if (focused) return true;
        }

        if (!focused) return false;

        if (cursorPos < 0) cursorPos = 0;
        if (cursorPos > text.length) cursorPos = cast(int)text.length;
        if (selectionAnchor < 0) selectionAnchor = 0;
        if (selectionAnchor > text.length) selectionAnchor = cast(int)text.length;

        if (event.type == EventType.keyPressed) {
            auto code = event.key.code;
            bool shift = (event.key.mods & Modifiers.Shift) != 0;
            bool ctrl = (event.key.mods & Modifiers.Ctrl) != 0;

            if (ctrl) {
                if (code == KeyCode.C) {
                    if (selectionAnchor != cursorPos) {
                        int start = min(selectionAnchor, cursorPos);
                        int end = max(selectionAnchor, cursorPos);
                        if (event.window !is null && event.window.platform !is null) {
                            event.window.platform.setClipboard(to!string(text[start .. end]));
                        }
                    }
                } else if (code == KeyCode.V) {
                    if (event.window !is null && event.window.platform !is null) {
                        dstring pasteText = event.window.platform.getClipboard().to!dstring;
                        if (pasteText.length > 0) {
                            deleteSelection();
                            int remaining = maxLength - cast(int)text.length;
                            if (pasteText.length > remaining) pasteText = pasteText[0 .. remaining];
                            
                            text = text[0 .. cursorPos] ~ pasteText ~ text[cursorPos .. $];
                            cursorPos += pasteText.length;
                            selectionAnchor = cursorPos;
                            resetCursorBlink();
                        }
                    }
                } else if (code == KeyCode.X) {
                    if (selectionAnchor != cursorPos) {
                        int start = min(selectionAnchor, cursorPos);
                        int end = max(selectionAnchor, cursorPos);
                        if (event.window !is null && event.window.platform !is null) {
                            event.window.platform.setClipboard(to!string(text[start .. end]));
                        }
                        deleteSelection();
                        resetCursorBlink();
                    }
                } else if (code == KeyCode.A) {
                    selectionAnchor = 0;
                    cursorPos = cast(int)text.length;
                    resetCursorBlink();
                }
            } else {
                if (code == KeyCode.Backspace) {
                    if (selectionAnchor != cursorPos) {
                        deleteSelection();
                    } else if (cursorPos > 0) {
                        text = text[0 .. cursorPos - 1] ~ text[cursorPos .. $];
                        cursorPos--;
                        selectionAnchor = cursorPos;
                    }
                    resetCursorBlink();
                } else if (code == KeyCode.Delete) {
                    if (selectionAnchor != cursorPos) {
                        deleteSelection();
                    } else if (cursorPos < text.length) {
                        text = text[0 .. cursorPos] ~ text[cursorPos + 1 .. $];
                    }
                    resetCursorBlink();
                } else if (code == KeyCode.ArrowLeft) {
                    if (cursorPos > 0) {
                        cursorPos--;
                    }
                    if (!shift) selectionAnchor = cursorPos;
                    resetCursorBlink();
                } else if (code == KeyCode.ArrowRight) {
                    if (cursorPos < text.length) {
                        cursorPos++;
                    }
                    if (!shift) selectionAnchor = cursorPos;
                    resetCursorBlink();
                } else if (code == KeyCode.Home) {
                    cursorPos = 0;
                    if (!shift) selectionAnchor = cursorPos;
                    resetCursorBlink();
                } else if (code == KeyCode.End) {
                    cursorPos = cast(int)text.length;
                    if (!shift) selectionAnchor = cursorPos;
                    resetCursorBlink();
                }
            }
        } else if (event.type == EventType.textInput) {
            dchar c = event.textInput.character;
            if (c >= 32) {
                deleteSelection();
                if (text.length < maxLength) {
                    text = text[0 .. cursorPos] ~ c ~ text[cursorPos .. $];
                    cursorPos++;
                    selectionAnchor = cursorPos;
                    resetCursorBlink();
                }
            }
        }
        return true;
    }

    override void draw(Surface surface) {
        int x = bounds.x;
        int y = bounds.y;
        int w = bounds.w;
        int h = bounds.h;

        if (cursorPos < 0) cursorPos = 0;
        if (cursorPos > text.length) cursorPos = cast(int)text.length;
        if (selectionAnchor < 0) selectionAnchor = 0;
        if (selectionAnchor > text.length) selectionAnchor = cast(int)text.length;

        Graphics.drawRect(surface, bgColor, Rect(x, y, w, h));
        
        Color border = focused ? focusColor : borderColor;

        Graphics.drawRect(surface, border, Rect(x, y, w, 1));
        Graphics.drawRect(surface, border, Rect(x, y + h - 1, w, 1));
        Graphics.drawRect(surface, border, Rect(x, y, 1, h));
        Graphics.drawRect(surface, border, Rect(x + w - 1, y, 1, h));

        if (font is null) return;

        int padding = 5;
        int fontSize = h - padding * 2;
        int contentW = w - padding * 2;

        Size cursorSize = font.getSize(to!string(text[0 .. cursorPos]), fontSize);
        int cursorXRel = cursorSize.w;

        if (cursorXRel - scrollX < 0) {
            scrollX = cursorXRel;
        } else if (cursorXRel - scrollX > contentW - 2) {
            scrollX = cursorXRel - (contentW - 2);
        }

        surface.setClip(Rect(x + padding, y + padding, contentW, fontSize));
        
        int startX = x + padding - scrollX;

        if (selectionAnchor != cursorPos) {
            int startIdx = min(selectionAnchor, cursorPos);
            int endIdx = max(selectionAnchor, cursorPos);
            
            Size startSize = font.getSize(to!string(text[0 .. startIdx]), fontSize);
            Size rangeSize = font.getSize(to!string(text[startIdx .. endIdx]), fontSize);
            
            int selX = startX + startSize.w;
            int selW = rangeSize.w;
            Graphics.drawRect(surface, selectionColor, Rect(selX, y + padding, selW, fontSize));
        }

        Surface textSurf = font.getText(to!string(text), textColor, fontSize);
        surface.blit(textSurf, startX, y + padding);

        if (showCursor) {
            int cursorX = startX + cursorXRel;
            int cursorY = y + padding;
            int cursorW = 2;
            int cursorH = fontSize;
            Graphics.drawRect(surface, textColor, Rect(cursorX, cursorY, cursorW, cursorH));
        }

        surface.resetClip();
    }
}
