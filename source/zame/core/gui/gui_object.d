module zame.core.gui.gui_object;

import std.variant;
import std.algorithm : sort;
import zame.core.common;
import zame.core.graphics;
import zame.core.platform;

abstract class GUIObject {
    uint id;
    Rect bounds;
    int layer = 0;
    bool visible = true;
    bool enabled = true;
    bool blocksInput = true;
    
    this() {
        static uint _nextId = 0;
        this.id = ++_nextId;
    }

    abstract void draw(Surface dest);
    abstract void update(float dt);
    abstract bool handleInput(Event event);
}

class GUIManager {
    GUIObject[] objects;
    Size size;
    Window targetWindow;

    this(Size size, Window targetWindow = null) {
        this.size = size;
        this.targetWindow = targetWindow;
    }

    void addObject(GUIObject obj) {
        objects ~= obj;
        sortObjects();
    }

    void removeObject(GUIObject obj) {
        import std.algorithm : remove;
        objects = objects.remove!(o => o.id == obj.id);
    }

    void sortObjects() {
        objects.sort!((a, b) => a.layer < b.layer);
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

        for (int i = cast(int)objects.length - 1; i >= 0; i--) {
            auto obj = objects[i];
            if (obj.enabled && obj.visible) {
                if (obj.handleInput(event)) {
                    if (obj.blocksInput) return true;
                }
            }
        }
        return false;
    }
}