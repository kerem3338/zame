module zame.core.gui.gui_object;

import std.variant;
import std.algorithm : sort;
import zame.core.common;
import zame.core.graphics;
import zame.core.platform;

enum Dock {
    None,
    Top,
    Bottom,
    Left,
    Right,
    Fill
}

enum LayoutType {
    Manual,
    Vertical,
    Horizontal
}

enum Anchor : uint {
    None = 0,
    Top = 1 << 0,
    Bottom = 1 << 1,
    Left = 1 << 2,
    Right = 1 << 3,
    All = Top | Bottom | Left | Right
}

abstract class GUIObject {
    uint id;
    Rect bounds;
    int layer = 0;
    bool visible = true;
    bool enabled = true;
    bool blocksInput = true;
    bool focusable = false;
    bool focused = false;
    GUIManager manager;
    GUIObject parent;
    
    Dock dock = Dock.None;
    uint anchor = Anchor.Top | Anchor.Left;
    LayoutType layoutType = LayoutType.Manual;
    int[4] margin = [0, 0, 0, 0]; // left, top, right, bottom
    int[4] padding = [0, 0, 0, 0]; // left, top, right, bottom
    int spacing = 5;
    
    @property Instance instance() { return manager ? manager.instance : null; }
    
    void setManager(GUIManager m) {
        this.manager = m;
    }

    void setParent(GUIObject p) {
        this.parent = p;
        if (p !is null && p.manager !is null) {
            setManager(p.manager);
        }
    }

    void focus() {
        if (manager !is null) {
            manager.setFocus(this);
        }
    }
    
    this() {
        static uint _nextId = 0;
        this.id = ++_nextId;
    }

    abstract void draw(Surface dest);
    abstract void update(float dt);
    abstract bool handleInput(Event event);

    void performLayout(Rect area) {
        // Base implementation does nothing, override in containers
    }

    void onFocusGained() {}
    void onFocusLost() {}

    void collectFocusables(ref GUIObject[] list) {
        if (!visible || !enabled) return;
        if (focusable) list ~= this;
    }
}

class GUIManager {
    GUIObject[] objects;
    Size size;
    Window targetWindow;
    Instance instance;
    GUIObject focusedObject;

    this(Instance instance, Size size, Window targetWindow = null) {
        this.instance = instance;
        this.size = size;
        this.targetWindow = targetWindow;
    }

    void addObject(GUIObject obj) {
        obj.setManager(this);
        objects ~= obj;
        sortObjects();
    }

    void removeObject(GUIObject obj) {
        import std.algorithm : remove;
        objects = objects.remove!(o => o.id == obj.id);
        
        // Clear focus if the object or any of its children was focused
        if (focusedObject !is null) {
            auto p = focusedObject;
            while (p !is null) {
                if (p == obj) {
                    setFocus(null);
                    break;
                }
                p = p.parent;
            }
        }
    }

    void sortObjects() {
        objects.sort!((a, b) => a.layer < b.layer);
    }

    void performLayout() {
        Rect clientArea = Rect(0, 0, cast(int)size.w, cast(int)size.h);
        layoutChildren(objects, clientArea);
    }

    static void layoutChildren(GUIObject[] children, Rect area) {
        Rect remaining = area;

        foreach (obj; children) {
            if (!obj.visible) continue;

            if (obj.dock == Dock.None) {
                // Apply anchors
                if (obj.anchor != (Anchor.Top | Anchor.Left)) {
                    int dx1 = 0, dy1 = 0, dx2 = 0, dy2 = 0;
                    
                    // This is a bit simplified as we don't store "original" bounds vs "current" bounds
                    // but usually performLayout is called when parent's size changes.
                    // For a robust system we'd need oldArea or originalBounds.
                    // However, let's implement basic anchoring relative to the area.
                }
                
                obj.performLayout(obj.bounds);
                continue;
            }

            Rect b = obj.bounds;
            final switch (obj.dock) {
                case Dock.Top:
                    obj.bounds = Rect(remaining.x + obj.margin[0], remaining.y + obj.margin[1], remaining.w - obj.margin[0] - obj.margin[2], b.h);
                    remaining.y += obj.bounds.h + obj.margin[1] + obj.margin[3];
                    remaining.h -= obj.bounds.h + obj.margin[1] + obj.margin[3];
                    break;
                case Dock.Bottom:
                    obj.bounds = Rect(remaining.x + obj.margin[0], remaining.y + remaining.h - b.h - obj.margin[3], remaining.w - obj.margin[0] - obj.margin[2], b.h);
                    remaining.h -= obj.bounds.h + obj.margin[1] + obj.margin[3];
                    break;
                case Dock.Left:
                    obj.bounds = Rect(remaining.x + obj.margin[0], remaining.y + obj.margin[1], b.w, remaining.h - obj.margin[1] - obj.margin[3]);
                    remaining.x += obj.bounds.w + obj.margin[0] + obj.margin[2];
                    remaining.w -= obj.bounds.w + obj.margin[0] + obj.margin[2];
                    break;
                case Dock.Right:
                    obj.bounds = Rect(remaining.x + remaining.w - b.w - obj.margin[2], remaining.y + obj.margin[1], b.w, remaining.h - obj.margin[1] - obj.margin[3]);
                    remaining.w -= obj.bounds.w + obj.margin[0] + obj.margin[2];
                    break;
                case Dock.Fill:
                    obj.bounds = Rect(remaining.x + obj.margin[0], remaining.y + obj.margin[1], remaining.w - obj.margin[0] - obj.margin[2], remaining.h - obj.margin[1] - obj.margin[3]);
                    // Fill consumes everything
                    break;
                case Dock.None: break;
            }
            
            obj.performLayout(obj.bounds);
        }
    }

    static void layoutChildrenLinear(GUIObject parent, GUIObject[] children, Rect area, bool vertical) {
        Rect current = Rect(area.x + parent.padding[0], area.y + parent.padding[1], area.w - parent.padding[0] - parent.padding[2], area.h - parent.padding[1] - parent.padding[3]);
        
        foreach (obj; children) {
            if (!obj.visible) continue;
            
            if (vertical) {
                obj.bounds = Rect(current.x + obj.margin[0], current.y + obj.margin[1], current.w - obj.margin[0] - obj.margin[2], obj.bounds.h);
                current.y += obj.bounds.h + obj.margin[1] + obj.margin[3] + parent.spacing;
            } else {
                obj.bounds = Rect(current.x + obj.margin[0], current.y + obj.margin[1], obj.bounds.w, current.h - obj.margin[1] - obj.margin[3]);
                current.x += obj.bounds.w + obj.margin[0] + obj.margin[2] + parent.spacing;
            }
            
            obj.performLayout(obj.bounds);
        }
    }

    void update(float dt) {
        foreach (obj; objects) {
            if (obj.enabled) {
                obj.update(dt);
            }
        }
    }

    void draw(Surface dest) {
        foreach (obj; objects) {
            if (obj.visible) {
                obj.draw(dest);
            }
        }
    }

    bool handleInput(Event event) {
        if (targetWindow !is null && event.window !is null && event.window !is targetWindow) {
            return false;
        }

        if (event.type == EventType.keyPressed && event.key.code == KeyCode.Tab) {
            cycleFocus(!(event.key.mods & Modifiers.Shift));
            return true;
        }

        // Route keyboard events to focused object first
        if (focusedObject !is null && focusedObject.enabled && focusedObject.visible) {
            if (event.type == EventType.keyPressed || event.type == EventType.keyReleased || event.type == EventType.textInput) {
                if (focusedObject.handleInput(event)) return true;
                if (focusedObject.blocksInput) return true;
            }
        }

        for (int i = cast(int)objects.length - 1; i >= 0; i--) {
            auto obj = objects[i];
            if (obj.enabled && obj.visible) {
                // Skip keyboard events already handled by focusedObject
                if (obj == focusedObject && (event.type == EventType.keyPressed || event.type == EventType.keyReleased || event.type == EventType.textInput)) continue;

                if (obj.handleInput(event)) {
                    if (event.type == EventType.mouseButtonPressed && obj.focusable) {
                        setFocus(obj);
                    }
                    if (obj.blocksInput) return true;
                }
            }
        }
        
        if (event.type == EventType.mouseButtonPressed) {
            setFocus(null);
        }

        return false;
    }

    void setFocus(GUIObject obj) {
        if (focusedObject == obj) return;

        if (focusedObject !is null) {
            focusedObject.focused = false;
            focusedObject.onFocusLost();
        }

        focusedObject = obj;

        if (focusedObject !is null) {
            if (focusedObject.focusable) {
                focusedObject.focused = true;
                focusedObject.onFocusGained();
            } else {
                focusedObject = null;
            }
        }
    }

    void cycleFocus(bool forward = true) {
        if (objects.length == 0) return;

        GUIObject[] focusables;
        foreach (obj; objects) {
            obj.collectFocusables(focusables);
        }

        if (focusables.length == 0) return;

        int currentIndex = -1;
        foreach (i, f; focusables) {
            if (f == focusedObject) {
                currentIndex = cast(int)i;
                break;
            }
        }

        if (forward) {
            currentIndex = (currentIndex + 1) % cast(int)focusables.length;
        } else {
            currentIndex = (currentIndex - 1 + cast(int)focusables.length) % cast(int)focusables.length;
        }

        setFocus(focusables[currentIndex]);
    }
}