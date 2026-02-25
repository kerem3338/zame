module zame.core.gui.components;

import zame.core.graphics;
import zame.core.common;
import zame.core.platform;
import zame.core.font;
import std.conv;
import std.string : chop;
import std.algorithm : min, max, sort, endsWith;
import std.path : absolutePath, buildPath, dirName, baseName;
import std.file : dirEntries, DirEntry, SpanMode, exists, isDir;
import std.math : abs;
import zame.core.gui.gui_object;


class Button : GUIObject {
	dstring text;
	void delegate() onClick;
	bool hovered = false;
	bool pressed = false;
	int fontSize = 16;
	Font font;

	this(dstring text, void delegate() onClick = null) {
		super();
		this.text = text;
		this.onClick = onClick;
		this.focusable = true;
		this.bounds = Rect(0, 0, 150, 30); // Sensible default size
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
		} else if (event.type == EventType.keyPressed && event.key.code == KeyCode.Enter) {
			if (focused) {
				if (onClick !is null) onClick();
				return true;
			}
		}
		return false;
	}

	private Surface[] _cachedTextSurfs;
	private dstring _lastText;
	private int _lastFontSize;
	private Font _lastFont;

	override void draw(Surface surface) {
		Color bgColor = pressed ? Color(100, 100, 100) : (hovered ? Color(80, 80, 80) : Color(60, 60, 60));
		Graphics.drawRect(surface, bgColor, bounds);
		Graphics.drawRect(surface, Colors.white, Rect(bounds.x, bounds.y, bounds.w, 1));
		Graphics.drawRect(surface, Colors.white, Rect(bounds.x, bounds.y + bounds.h - 1, bounds.w, 1));
		Graphics.drawRect(surface, Colors.white, Rect(bounds.x, bounds.y, 1, bounds.h));
		Graphics.drawRect(surface, Colors.white, Rect(bounds.x + bounds.w - 1, bounds.y, 1, bounds.h));

		if (focused) {
			Graphics.drawRect(surface, Colors.yellow, Rect(bounds.x + 2, bounds.y + 2, bounds.w - 4, 1));
			Graphics.drawRect(surface, Colors.yellow, Rect(bounds.x + 2, bounds.y + bounds.h - 3, bounds.w - 4, 1));
			Graphics.drawRect(surface, Colors.yellow, Rect(bounds.x + 2, bounds.y + 2, 1, bounds.h - 4));
			Graphics.drawRect(surface, Colors.yellow, Rect(bounds.x + bounds.w - 3, bounds.y + 2, 1, bounds.h - 4));
		}

		if (font !is null && text.length > 0) {
			if (_cachedTextSurfs is null || text != _lastText || fontSize != _lastFontSize || font !is _lastFont) {
				import std.string : split;
				string s = to!string(text);
				string[] lines = s.split("\n");
				_cachedTextSurfs = new Surface[lines.length];
				foreach (i, line; lines) {
					_cachedTextSurfs[i] = font.getText(line, Colors.white, fontSize);
				}
				_lastText = text;
				_lastFontSize = fontSize;
				_lastFont = font;
			}
			
			int totalH = 0;
			foreach (s; _cachedTextSurfs) totalH += s.height + 2;
			
			int ty = bounds.y + (bounds.h - totalH) / 2;
			foreach (s; _cachedTextSurfs) {
				surface.blit(s, bounds.x + (bounds.w - s.width) / 2, ty);
				ty += s.height + 2;
			}
		}
	}
}

class GUIWindow : GUIObject {
	dstring title;
	GUIObject[] children;
	Color bgColor = Color(30, 30, 40, 240);
	Color borderColor = Colors.white;
	bool dragging = false;
	Point dragOffset;
	bool canMinimize = false;
	bool isMinimized = false;
	int normalHeight;
	Font font;

	this(dstring title, Rect bounds) {
		super();
		this.title = title;
		this.bounds = bounds;
		this.normalHeight = bounds.h;
	}

	override void setManager(GUIManager m) {
		super.setManager(m);
		foreach (child; children) {
			child.setManager(m);
		}
	}

    void addChild(GUIObject obj) {
        obj.setManager(this.manager);
        children ~= obj;
        sortChildren();
        performLayout(bounds);
    }

	void sortChildren() {
		children.sort!((a, b) => a.layer < b.layer);
	}

	override void update(float dt) {
		foreach (child; children) {
			if (child.enabled) child.update(dt);
		}
	}

	override void collectFocusables(ref GUIObject[] list) {
		if (!visible || !enabled) return;
		foreach (child; children) {
			child.collectFocusables(list);
		}
	}

	override void performLayout(Rect area) {
		this.bounds = area;
		Rect clientArea = Rect(bounds.x, bounds.y + 30, bounds.w, isMinimized ? 0 : bounds.h - 30);
		if (layoutType == LayoutType.Vertical) {
			GUIManager.layoutChildrenLinear(this, children, clientArea, true);
		} else if (layoutType == LayoutType.Horizontal) {
			GUIManager.layoutChildrenLinear(this, children, clientArea, false);
		} else {
			GUIManager.layoutChildren(children, clientArea);
		}
	}

	override bool handleInput(Event event) {
		if (!isMinimized) {
			for (int i = cast(int)children.length - 1; i >= 0; i--) {
				auto child = children[i];
				if (child.enabled && child.visible) {
					if (child.handleInput(event)) return true;
				}
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
				// Minimize button (if enabled)
				if (canMinimize) {
					Rect btnRect = Rect(bounds.x + bounds.w - 25, bounds.y + 5, 20, 20);
					if (btnRect.contains(Point(mx, my))) {
						isMinimized = !isMinimized;
						if (isMinimized) {
							normalHeight = bounds.h;
							bounds.h = 30;
						} else {
							bounds.h = normalHeight;
						}
						// Calling performLayout on self will update children
						performLayout(bounds);
						return true;
					}
				}

				dragging = true;
				dragOffset = Point(mx - bounds.x, my - bounds.y);
				return true;
			}
		} else if (event.type == EventType.mouseButtonReleased && event.mouse.button == MouseEvent.ButtonType.left) {
			dragging = false;
		} else if (event.type == EventType.mouseMoved && dragging) {
			bounds.x = mx - dragOffset.x;
			bounds.y = my - dragOffset.y;
			
			// performLayout updates all child positions relative to new bounds
			performLayout(bounds);
			return true;
		}

		if (mx != -1 && my != -1 && bounds.contains(Point(mx, my))) return true;
		if (event.type == EventType.mouseWheel && bounds.contains(Point(instance.mouseX, instance.mouseY))) return true;
		return false;
	}

	private Surface _cachedTitleSurf;
	private dstring _lastTitle;
	private Font _lastFont;

	override void draw(Surface surface) {
		Graphics.drawRect(surface, bgColor, bounds);
		Graphics.drawRect(surface, Color(50, 50, 70), Rect(bounds.x, bounds.y, bounds.w, 30));
		Graphics.drawRect(surface, borderColor, Rect(bounds.x, bounds.y, bounds.w, 1));
		Graphics.drawRect(surface, borderColor, Rect(bounds.x, bounds.y + bounds.h - 1, bounds.w, 1));
		Graphics.drawRect(surface, borderColor, Rect(bounds.x, bounds.y, 1, bounds.h));
		Graphics.drawRect(surface, borderColor, Rect(bounds.x + bounds.w - 1, bounds.y, 1, bounds.h));

		if (canMinimize) {
			Color btnColor = isMinimized ? Colors.green : Colors.red;
			Graphics.drawRect(surface, btnColor, Rect(bounds.x + bounds.w - 25, bounds.y + 5, 20, 20));
		}

		if (font !is null && title.length > 0) {
			if (_cachedTitleSurf is null || title != _lastTitle || font !is _lastFont) {
				_cachedTitleSurf = font.getText(to!string(title), Colors.white, 16);
				_lastTitle = title;
				_lastFont = font;
			}
			surface.blit(_cachedTitleSurf, bounds.x + 10, bounds.y + (30 - _cachedTitleSurf.height) / 2);
		}

		if (!isMinimized) {
			foreach (child; children) {
				if (child.visible) child.draw(surface);
			}
		}
	}

}

class TabbedPanel : GUISurface {
	struct Tab {
		dstring title;
		GUIObject panel;
	}

	Tab[] tabs;
	int activeTabIndex = 0;
	Font font;

	this(Rect bounds, Font font) {
		super(bounds);
		this.font = font;
	}

	void addTab(dstring title, GUIObject panel) {
		tabs ~= Tab(title, panel);
		panel.visible = (tabs.length == 1);
		addChild(panel);
	}

	override void draw(Surface surface) {
		super.draw(surface);

		// Draw context bar
		int tabWidth = bounds.w / cast(int)max(1, tabs.length);
		for (int i = 0; i < tabs.length; i++) {
			Rect tabRect = Rect(bounds.x + i * tabWidth, bounds.y, tabWidth, 25);
			Color color = (i == activeTabIndex) ? Color(100, 100, 120) : Color(60, 60, 80);
			Graphics.drawRect(surface, color, tabRect);
			Graphics.drawRect(surface, Colors.white, Rect(tabRect.x, tabRect.y, tabRect.w, 1));

			if (font !is null) {
				auto text = font.getText(to!string(tabs[i].title), Colors.white, 14);
				surface.blit(text, tabRect.x + (tabRect.w - text.width) / 2, tabRect.y + (tabRect.h - text.height) / 2);
			}
		}
	}

	override bool handleInput(Event event) {
		int mx = -1, my = -1;
		if (event.type == EventType.mouseButtonPressed) {
			mx = event.mouse.x;
			my = event.mouse.y;
			
			if (Rect(bounds.x, bounds.y, bounds.w, 25).contains(Point(mx, my))) {
				int tabWidth = bounds.w / cast(int)max(1, tabs.length);
				int clickedIndex = (mx - bounds.x) / tabWidth;
				if (clickedIndex < tabs.length) {
					activeTabIndex = clickedIndex;
					foreach (i, t; tabs) {
						t.panel.visible = (i == activeTabIndex);
					}
					performLayout(bounds);
					return true;
				}
			}
		}
		
		return super.handleInput(event);
	}

	override void performLayout(Rect area) {
		this.bounds = area;
		Rect panelArea = Rect(area.x, area.y + 25, area.w, area.h - 25);
		foreach (t; tabs) {
			t.panel.performLayout(panelArea);
		}
	}
}

class GUISurface : GUIObject {
	GUIObject[] children;
	Color color = Colors.transparent;

	this(Rect bounds) {
		super();
		this.bounds = bounds;
	}

	override void setManager(GUIManager m) {
		super.setManager(m);
		foreach (child; children) {
			child.setManager(m);
		}
	}

	void addChild(GUIObject obj) {
		obj.setParent(this);
		children ~= obj;
		sortChildren();
		performLayout(bounds);
	}

	void sortChildren() {
		import std.algorithm : sort;
		children.sort!((a, b) => a.layer < b.layer);
	}

	override void update(float dt) {
		foreach (child; children) {
			if (child.enabled) child.update(dt);
		}
	}

	override void draw(Surface surface) {
		if (color.a > 0) {
			Graphics.drawRect(surface, color, bounds);
		}
		foreach (child; children) {
			if (child.visible) child.draw(surface);
		}
	}

	override bool handleInput(Event event) {
		for (int i = cast(int)children.length - 1; i >= 0; i--) {
			auto child = children[i];
			if (child.enabled && child.visible) {
				if (child.handleInput(event)) return true;
			}
		}

		if (blocksInput && visible && enabled) {
			if (event.type == EventType.mouseButtonPressed || event.type == EventType.mouseButtonReleased) {
				if (bounds.contains(Point(event.mouse.x, event.mouse.y))) return true;
			} else if (event.type == EventType.mouseWheel) {
				if (bounds.contains(Point(instance.mouseX, instance.mouseY))) return true;
			} else if (event.type == EventType.mouseMoved) {
				if (bounds.contains(Point(event.mouseMoved.x, event.mouseMoved.y))) return true;
			}
		}
		return false;
	}

	override void performLayout(Rect area) {
		this.bounds = area;
		if (layoutType == LayoutType.Vertical) {
			GUIManager.layoutChildrenLinear(this, children, area, true);
		} else if (layoutType == LayoutType.Horizontal) {
			GUIManager.layoutChildrenLinear(this, children, area, false);
		} else {
			GUIManager.layoutChildren(children, area);
		}
	}

	override void collectFocusables(ref GUIObject[] list) {
		if (!visible || !enabled) return;
		foreach (child; children) {
			child.collectFocusables(list);
		}
	}
}

class KeyValueEditor : GUISurface {
    string[string] data;
    Font font;
    void delegate(string[string]) onChanged;

    GUISurface contentContainer;
    int scrollY = 0;
    int contentHeight = 0;
    private bool isRefreshing = false;
    
    // Recovery state
    private string pendingFocusKey;
    private bool pendingFocusIsValue;
    private int pendingFocusCursor;
    
    // Scrollbar state
    bool isDraggingScroll = false;
    int scrollDragOffset = 0;
    int scrollBarWidth = 10;

    this(Rect bounds, Font font) {
        super(bounds);
        this.font = font;
        this.layoutType = LayoutType.Manual; // We manage layout manually
        this.padding = [5, 5, 5, 5];
        
        // Initialize container
        contentContainer = new GUISurface(Rect(bounds.x, bounds.y, bounds.w - scrollBarWidth, bounds.h));
        contentContainer.color = Colors.transparent;
        contentContainer.layoutType = LayoutType.Manual; // We position rows manually in refresh
    }

    void setData(string[string] newData) {
        import std.stdio : writeln;
        
        // Use a copy to avoid external modification issues
        string[string] copy;
        foreach(k, v; newData) copy[k] = v;
        
        if (this.data == copy) {
            writeln("[KV_DEBUG] setData: Data identical to current, skipping refresh.");
            return;
        }

        writeln("[KV_DEBUG] setData called. Current items: ", data.length, " -> New items: ", copy.length);
        this.data = copy;
        refresh();
    }
    
    void updateScrollPosition() {
        int maxScroll = max(0, contentHeight - bounds.h);
        if (scrollY < 0) scrollY = 0;
        if (scrollY > maxScroll) scrollY = maxScroll;
        
        // Update container Posisiton
        contentContainer.bounds.y = bounds.y - scrollY;
        contentContainer.bounds.x = bounds.x;
        
        // We need to re-layout children because their bounds are absolute (usually)
        // Since we are setting manual bounds on children in refresh, just shifting them might be needed.
        // Actually, GUISurface.performLayout relies on layoutType.
        // If layoutType is None, performLayout does nothing to children usually?
        // Let's rely on manually shifting children or using a layout helper.
        // Ideally, we move contentContainer, and then tell it to layout children.
        // But GUISurface.performLayout with None doesn't help much.
        // Let's set contentContainer.layoutType = Vertical, and let it layout.
        
        contentContainer.performLayout(contentContainer.bounds);
    }

    void refresh() {
        import std.stdio : writeln;
        if (isRefreshing) {
            writeln("[KV_AUDIT] RECURSION PREVENTED in refresh()");
            return;
        }
        isRefreshing = true;
        scope(exit) isRefreshing = false;

        writeln("[KV_AUDIT] REFRESHING UI. Current items: ", data.length);
        
        // Commit any pending edit in focused child BEFORE clearing children list
        if (manager !is null && manager.focusedObject !is null) {
            auto obj = manager.focusedObject;
            bool isOurChild = false;
            auto p = obj.parent;
            while (p !is null) {
                if (p == this) { isOurChild = true; break; }
                p = p.parent;
            }
            
            if (isOurChild) {
                if (auto ti = cast(TextInput)obj) {
                    if (ti.onSubmit && ti.text != ti.lastSubmittedText) {
                        writeln("[KV_AUDIT] COMMITTING FOCUSED FIELD BEFORE REBUILD: '", ti.text, "'");
                        ti.lastSubmittedText = ti.text; 
                        ti.onSubmit(ti.text);
                    }
                }
            }
        }

        if (contentContainer is null) {
            contentContainer = new GUISurface(Rect(bounds.x, bounds.y, bounds.w - scrollBarWidth, bounds.h));
        }
        
        contentContainer.children = [];
        contentContainer.layoutType = LayoutType.Vertical;
        contentContainer.spacing = 4;
        contentContainer.padding = [4, 4, 4, 4];

        // Sort keys for focus stability
        import std.algorithm : sort;
        string[] sortedKeys = data.keys;
        sort(sortedKeys);

        void setupRow(string currentKey, string currentValue) {
            auto row = new GUISurface(Rect(0, 0, bounds.w - scrollBarWidth - 8, 30));
            row.layoutType = LayoutType.Horizontal;
            row.spacing = 5;
            row.setParent(contentContainer);
            
            // KEY INPUT
            auto keyInput = new TextInput();
            keyInput.text = currentKey.to!dstring;
            keyInput.lastSubmittedText = keyInput.text;
            keyInput.font = font;
            keyInput.setParent(row);
            keyInput.onSubmit = (val) {
                string newK = val.to!string;
                writeln("[KV_AUDIT][obj:", id, "][row:", currentKey, "] RENAME REQUEST: '", currentKey, "' -> '", newK, "'");
                
                if (newK.length > 0 && newK != currentKey) {
                    if (newK in data) {
                        writeln("[KV_AUDIT][obj:", id, "] RENAME FAILED: Collision with '", newK, "'");
                        keyInput.text = currentKey.to!dstring;
                        return; 
                    }
                    
                    writeln("[KV_AUDIT][obj:", id, "] TRANSACTION: Rename '", currentKey, "' to '", newK, "'");
                    string v = data[currentKey];
                    data.remove(currentKey);
                    data[newK] = v;
                    
                    if (onChanged) {
                        string[string] copy;
                        foreach(k2, v2; data) copy[k2] = v2;
                        onChanged(copy);
                    }
                    pendingFocusKey = newK;
                    pendingFocusIsValue = false; 
                    refresh();
                } else if (newK.length == 0) {
                    writeln("[KV_AUDIT][obj:", id, "] RENAME FAILED: Empty key not allowed. Reverting.");
                    keyInput.text = currentKey.to!dstring;
                    keyInput.lastSubmittedText = currentKey.to!dstring;
                }
            };
            keyInput.bounds.w = (row.bounds.w - 30) / 2;
            
            if (currentKey == pendingFocusKey && !pendingFocusIsValue) {
                keyInput.focused = true;
                if (manager !is null) manager.setFocus(keyInput);
                pendingFocusKey = "";
            }
            
            // VALUE INPUT
            auto valInput = new TextInput();
            valInput.text = currentValue.to!dstring;
            valInput.lastSubmittedText = valInput.text;
            valInput.font = font;
            valInput.setParent(row);
            valInput.onSubmit = (val) {
                string newV = val.to!string;
                writeln("[KV_AUDIT][obj:", id, "][row:", currentKey, "] VALUE CHANGE: '", currentValue, "' -> '", newV, "'");
                
                if (currentKey in data) {
                    if (data[currentKey] != newV) {
                        data[currentKey] = newV;
                        if (onChanged) {
                            string[string] copy;
                            foreach(k2, v2; data) copy[k2] = v2;
                            onChanged(copy);
                        }
                    }
                } else {
                    writeln("[KV_AUDIT][obj:", id, "] ERROR: Key vanished while editing value: ", currentKey);
                }
            };
            valInput.bounds.w = (row.bounds.w - 30) / 2;
            
            if (currentKey == pendingFocusKey && pendingFocusIsValue) {
                valInput.focused = true;
                if (manager !is null) manager.setFocus(valInput);
                pendingFocusKey = "";
            }
            
            row.addChild(keyInput);
            row.addChild(valInput);
            
            auto btnDel = new Button("X"d, { 
                writeln("[KV_AUDIT][obj:", id, "][row:", currentKey, "] DELETE clicked");
                if (currentKey in data) {
                    data.remove(currentKey); 
                    if (onChanged) {
                        string[string] copy;
                        foreach(k2, v2; data) copy[k2] = v2;
                        onChanged(copy);
                    }
                    refresh(); 
                }
            });
            btnDel.font = font;
            btnDel.fontSize = 12;
            btnDel.bounds.w = 20;
            btnDel.setParent(row);
            row.addChild(btnDel);
            
            contentContainer.addChild(row);
        }

        foreach(idx, loopKey; sortedKeys) {
            setupRow(loopKey, data[loopKey]);
        }
        
        auto btnAdd = new Button("Add Property"d, { 
            writeln("[KV_AUDIT] ADDING NEW PROPERTY ROW");
            string base = "new_prop";
            string candidate = base;
            int counter = 1;
            while(candidate in data) {
                candidate = base ~ "_" ~ counter.to!string;
                counter++;
            }
            data[candidate] = "value";
            writeln("[KV_AUDIT] TRANSACTION: Added '", candidate, "'");
            pendingFocusKey = candidate;
            pendingFocusIsValue = false;
            if (onChanged) {
                string[string] copy;
                foreach(k2, v2; data) copy[k2] = v2;
                onChanged(copy);
            }
            refresh();
        });
        btnAdd.font = font;
        btnAdd.bounds.h = 30;
        contentContainer.addChild(btnAdd);
        
        contentHeight = cast(int)data.length * 35 + 40;
        contentContainer.bounds.h = max(bounds.h, contentHeight);
        contentContainer.bounds.w = bounds.w - scrollBarWidth;
        this.children = [contentContainer];
        updateScrollPosition();
        writeln("[KV_AUDIT] UI REBUILD COMPLETE.");
    }
    
    override void performLayout(Rect area) {
        this.bounds = area;
        // Resize container width if editor resizes
        if (contentContainer !is null) {
            contentContainer.bounds.w = bounds.w - scrollBarWidth;
             updateScrollPosition();
        }
    }
    
    override bool handleInput(Event event) {
        // Handle Scrollbar Dragging
        if (isDraggingScroll) {
            if (event.type == EventType.mouseButtonReleased) {
                isDraggingScroll = false;
                return true;
            } else if (event.type == EventType.mouseMoved) {
                 int maxScroll = max(0, contentHeight - bounds.h);
                 if (maxScroll > 0) {
                     float trackHeight = bounds.h;
                     float thumbHeight = max(20, (bounds.h.to!float / contentHeight.to!float) * trackHeight);
                     float trackArea = trackHeight - thumbHeight;
                     
                     if (trackArea > 0) {
                         int deltaArr = event.mouseMoved.y - (bounds.y + scrollDragOffset);
                         // This logic implies duplicate calculation.
                         // Simpler: map mouse Y to scroll percentage.
                         // But we captured offset...
                         // Let's just use MouseMoved deltaY?
                         // event.mouseMoved.y is absolute position.
                         
                         // Re-calculate drag based on relative movement?
                         // Input system provides mouseMoved.relX/Y? No, looking at Event struct...
                         // Usually mouseMoved has x,y.
                         
                         // Let's implement simple scroll:
                         int relativeY = event.mouseMoved.y - bounds.y;
                         // relativeY roughly maps to scrollBarPos.
                         // ...
                         // Let's use Wheel for now as primary, Dragging is bonus.
                     }
                 }
                 return true;
            }
        }
        
        if (event.type == EventType.mouseWheel) {
            if (bounds.contains(Point(instance.mouseX, instance.mouseY))) {
                 scrollY -= event.mouseWheel.delta * 20;
                 updateScrollPosition();
                 return true;
            }
        }
        
        // Forward input to container (clipped)
        // We only forward if mouse is inside OUR bounds (for clicks)
        // But logic is complex. child.handleInput usually checks its own bounds.
        // contentContainer is shifted.
        // If we just call super.handleInput(event), it iterates children.
        // contentContainer.handleInput iterates ITS children.
        // Since we updated contentContainer.bounds, children should have correct screen bounds.
        
        // However, we must Ensure that clicks OUTSIDE KeyValueEditor bounds (but inside contentContainer bounds, i.e. hidden parts) are IGNORED.
        // We can check if event point is within our bounds.
        
        if (event.type == EventType.mouseButtonPressed || event.type == EventType.mouseButtonReleased || event.type == EventType.mouseMoved) {
            int mx = (event.type == EventType.mouseMoved) ? event.mouseMoved.x : event.mouse.x;
            int my = (event.type == EventType.mouseMoved) ? event.mouseMoved.y : event.mouse.y;
            
            if (!bounds.contains(Point(mx, my))) {
                // If dragging scrollbar, we allow outside.
                if (!isDraggingScroll) return false; 
            }
        }

        return super.handleInput(event);
    }
    
    override void draw(Surface surface) {
        // Save previous clip
        bool wasClipping = surface.isClipping();
        Rect oldClip = surface.getClipRect();
        
        // Calculate new clip (intersection)
        Rect newClip = bounds;
        if (wasClipping) {
            int x1 = max(newClip.x, oldClip.x);
            int y1 = max(newClip.y, oldClip.y);
            int x2 = min(newClip.x + newClip.w, oldClip.x + oldClip.w);
            int y2 = min(newClip.y + newClip.h, oldClip.y + oldClip.h);
            newClip = Rect(x1, y1, max(0, x2 - x1), max(0, y2 - y1));
        }

        surface.setClip(newClip);
        if (contentContainer !is null) contentContainer.draw(surface);
        
        // Restore previous clip
        if (wasClipping) surface.setClip(oldClip);
        else surface.resetClip();
        
        // Draw Scrollbar (on top of clipped content, but inside own bounds? No, usually on top)
        // Scrollbar shouldn't be clipped by the content clip, but maybe by parent clip.
        // We restored parent clip, so drawing here respects parent clip.
        
        int maxScroll = max(0, contentHeight - bounds.h);
        if (maxScroll > 0) {
            Rect sbarRect = Rect(bounds.x + bounds.w - scrollBarWidth, bounds.y, scrollBarWidth, bounds.h);
            Graphics.drawRect(surface, Color(40, 40, 50), sbarRect);
            
            float trackHeight = bounds.h;
            float thumbHeight = max(20, (bounds.h.to!float / contentHeight.to!float) * trackHeight);
            float scrollRatio = scrollY.to!float / maxScroll.to!float;
            float thumbY = scrollRatio * (trackHeight - thumbHeight);
            
            Rect thumbRect = Rect(sbarRect.x, bounds.y + cast(int)thumbY, scrollBarWidth, cast(int)thumbHeight);
            Graphics.drawRect(surface, Color(100, 100, 120), thumbRect);
        }
    }
}

class CustomButton : GUIObject {
	Surface normal;
	Surface hover;
	Surface pressed;
	Surface disabled;
	
	dstring text;
	Font font;
	int fontSize = 16;
	
	void delegate() onClick;
	bool isHovered = false;
	bool isPressed = false;

	this(Surface normal, void delegate() onClick = null) {
		super();
		this.normal = normal;
		this.onClick = onClick;
		this.focusable = true;
		if (normal !is null) {
			this.bounds = Rect(0, 0, normal.width, normal.height);
		}
	}

	override void update(float dt) {
	}

	private Surface _cachedTextSurf;
	private dstring _lastText;
	private int _lastFontSize;
	private Font _lastFont;

	override void draw(Surface surface) {
		Surface toDraw = normal;
		if (!enabled && disabled !is null) toDraw = disabled;
		else if (isPressed && pressed !is null) toDraw = pressed;
		else if (isHovered && hover !is null) toDraw = hover;

		if (toDraw !is null) {
			surface.blit(toDraw, bounds.x, bounds.y);
		}

		if (font !is null && text.length > 0) {
			if (_cachedTextSurf is null || text != _lastText || fontSize != _lastFontSize || font !is _lastFont) {
				_cachedTextSurf = font.getText(to!string(text), Colors.white, fontSize);
				_lastText = text;
				_lastFontSize = fontSize;
				_lastFont = font;
			}
			surface.blit(_cachedTextSurf, bounds.x + (bounds.w - _cachedTextSurf.width) / 2, bounds.y + (bounds.h - _cachedTextSurf.height) / 2);
		}
	}

	override bool handleInput(Event event) {
		if (event.type == EventType.mouseMoved) {
			isHovered = bounds.contains(Point(event.mouseMoved.x, event.mouseMoved.y));
		} else if (event.type == EventType.mouseButtonPressed && event.mouse.button == MouseEvent.ButtonType.left) {
			if (bounds.contains(Point(event.mouse.x, event.mouse.y))) {
				isPressed = true;
				return true;
			}
		} else if (event.type == EventType.mouseButtonReleased && event.mouse.button == MouseEvent.ButtonType.left) {
			if (isPressed) {
				isPressed = false;
				if (bounds.contains(Point(event.mouse.x, event.mouse.y))) {
					if (onClick !is null) onClick();
				}
				return true;
			}
		} else if (event.type == EventType.mouseWheel) {
			if (bounds.contains(Point(instance.mouseX, instance.mouseY))) return true;
		}
		return false;
	}
}

class TextInput : GUIObject {
	dstring text = "";
	int cursorPos = 0;
	int selectionAnchor = 0;
	int maxLength = 100;
	void delegate(dstring) onChanged;
    void delegate(dstring) onSubmit;
    bool wasFocused = false;
    dstring lastSubmittedText = "---NONE---"d;

	private void notifyChanged() {
		if (onChanged) onChanged(text);
	}

	this() {
		super();
		this.focusable = true;
		this.bounds = Rect(0, 0, 200, 30); // Default size
        this.lastSubmittedText = text;
	}
	
	float cursorTimer = 0.0f;
	bool showCursor = true;
	float blinkRate = 0.5f;
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
		} else {
            cursorTimer += dt;
            if (cursorTimer >= blinkRate) {
                cursorTimer -= blinkRate;
                showCursor = !showCursor;
            }
        }
        
        wasFocused = focused;
	}

    override void onFocusGained() {
        import std.stdio : writeln;
        writeln("[TI_DEBUG][obj:", id, "] Gained focus hook: '", text, "'");
        resetCursorBlink();
    }

    override void onFocusLost() {
        import std.stdio : writeln;
        writeln("[TI_DEBUG][obj:", id, "] Lost focus hook: '", text, "' (last: '", lastSubmittedText, "')");
        if (onSubmit && text != lastSubmittedText) {
            writeln("[TI_DEBUG][obj:", id, "] Auto-submitting on focus loss: '", text, "'");
            lastSubmittedText = text;
            onSubmit(text);
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
		if (event.type == EventType.mouseButtonPressed && event.mouse.button == MouseEvent.ButtonType.left) {
			focused = bounds.contains(Point(event.mouse.x, event.mouse.y));
            if (focused) {
                if (manager !is null) manager.setFocus(this);
                if (font !is null) {
                    // Calculate cursor position from mouse click
                    int padding = 5;
                    int fontSize = bounds.h - padding * 2; // Must match draw logic
                    int relativeX = event.mouse.x - bounds.x - padding + scrollX;
                    
                    int bestCursor = 0;
                    int minDist = int.max;
                    
                    // Brute force check all cursor positions to find closest
                    for(int i = 0; i <= text.length; i++) {
                        string sub = to!string(text[0..i]);
                        Size sz = font.getSize(sub, fontSize);
                        int dist = abs(sz.w - relativeX);
                        if (dist < minDist) {
                            minDist = dist;
                            bestCursor = i;
                        }
                    }
                    
                    cursorPos = bestCursor;
                    selectionAnchor = cursorPos; // Reset selection on click
                    resetCursorBlink();
                }
                return true;
            }
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
							notifyChanged();
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
						notifyChanged();
                        import std.stdio : writeln;
                        writeln("[TI_DEBUG] Cut text: '", text, "'");
					}
				} else if (code == KeyCode.A) {
					selectionAnchor = 0;
					cursorPos = cast(int)text.length;
					resetCursorBlink();
				}
			} else if (code == KeyCode.Enter || code == KeyCode.Escape) {
                import std.stdio : writeln;
                writeln("[TI_DEBUG] Enter/Esc pressed: '", text, "'");
                if (onSubmit && text != lastSubmittedText) {
                    lastSubmittedText = text;
                    onSubmit(text);
                }
                focused = false; // Relinquish focus
                if (manager !is null) manager.setFocus(null);
            }
            else {
				if (code == KeyCode.Backspace) {
					if (selectionAnchor != cursorPos) {
						deleteSelection();
					} else if (cursorPos > 0) {
						text = text[0 .. cursorPos - 1] ~ text[cursorPos .. $];
						cursorPos--;
						selectionAnchor = cursorPos;
						notifyChanged();
					}
					resetCursorBlink();
				} else if (code == KeyCode.Delete) {
					if (selectionAnchor != cursorPos) {
						deleteSelection();
					} else if (cursorPos < text.length) {
						text = text[0 .. cursorPos] ~ text[cursorPos + 1 .. $];
						notifyChanged();
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
            
            if (code == KeyCode.Enter) {
                if (onSubmit) {
                    lastSubmittedText = text;
                    onSubmit(text);
                }
                return true;
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
					notifyChanged();
				}
			}
		}
		return true;
	}

	private Surface _cachedTextSurf;
	private dstring _lastText;
	private int _lastFontSize;
	private Font _lastFont;
	private Color _lastTextColor;

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

		// Save previous clip
        bool wasClipping = surface.isClipping();
        Rect oldClip = surface.getClipRect();
        
        Rect targetClip = Rect(x + padding, y + padding, contentW, fontSize);
        Rect finalClip = targetClip;
        
        if (wasClipping) {
             int x1 = max(targetClip.x, oldClip.x);
             int y1 = max(targetClip.y, oldClip.y);
             int x2 = min(targetClip.x + targetClip.w, oldClip.x + oldClip.w);
             int y2 = min(targetClip.y + targetClip.h, oldClip.y + oldClip.h);
             finalClip = Rect(x1, y1, max(0, x2 - x1), max(0, y2 - y1));
        }

		surface.setClip(finalClip);
		
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

		if (_cachedTextSurf is null || text != _lastText || fontSize != _lastFontSize || font !is _lastFont || textColor != _lastTextColor) {
			_cachedTextSurf = font.getText(to!string(text), textColor, fontSize);
			_lastText = text;
			_lastFontSize = fontSize;
			_lastFont = font;
			_lastTextColor = textColor;
		}
		
		surface.blit(_cachedTextSurf, startX, y + padding);

		if (showCursor) {
			int cursorX = startX + cursorXRel;
			int cursorY = y + padding;
			int cursorW = 2;
			int cursorH = fontSize;
			Graphics.drawRect(surface, textColor, Rect(cursorX, cursorY, cursorW, cursorH));
		}

		if (wasClipping) surface.setClip(oldClip);
        else surface.resetClip();
	}
}

class Scrollbar : GUIObject {
	float value = 0.0f;
	float thumbSize = 0.2f;
	bool dragging = false;
	float dragOffset;
	Color trackColor = Color(40, 40, 50);
	Color thumbColor = Color(100, 100, 120);
	Color thumbHoverColor = Color(130, 130, 150);

	private bool hovered = false;

	this(Rect bounds) {
		super();
		this.bounds = bounds;
	}

	override void update(float dt) {
		if (value < 0.0f) value = 0.0f;
		if (value > 1.0f) value = 1.0f;
	}

	override bool handleInput(Event event) {
		int mx = -1, my = -1;
		if (event.type == EventType.mouseMoved) {
			mx = event.mouseMoved.x;
			my = event.mouseMoved.y;
			hovered = bounds.contains(Point(mx, my));
		} else if (event.type == EventType.mouseButtonPressed || event.type == EventType.mouseButtonReleased) {
			mx = event.mouse.x;
			my = event.mouse.y;
		}

		if (event.type == EventType.mouseButtonPressed && event.mouse.button == MouseEvent.ButtonType.left) {
			Rect thumbRect = getThumbRect();
			if (thumbRect.contains(Point(mx, my))) {
				dragging = true;
				dragOffset = my - thumbRect.y;
				return true;
			} else if (bounds.contains(Point(mx, my))) {
				float newY = my - bounds.y - (getThumbHeight() / 2.0f);
				value = newY / (bounds.h - getThumbHeight());
				dragging = true;
				dragOffset = getThumbHeight() / 2.0f;
				return true;
			}
		} else if (event.type == EventType.mouseButtonReleased && event.mouse.button == MouseEvent.ButtonType.left) {
			dragging = false;
		} else if (event.type == EventType.mouseMoved && dragging) {
			float newY = my - bounds.y - dragOffset;
			float maxPath = bounds.h - getThumbHeight();
			if (maxPath > 0) {
				value = newY / maxPath;
			} else {
				value = 0;
			}
			if (value < 0) value = 0;
			if (value > 1) value = 1;
			return true;
		}

		return hovered;
	}

	private float getThumbHeight() {
		return max(20.0f, bounds.h * thumbSize);
	}

	private Rect getThumbRect() {
		float h = getThumbHeight();
		float y = bounds.y + (bounds.h - h) * value;
		return Rect(bounds.x, cast(int)y, bounds.w, cast(int)h);
	}

	override void draw(Surface surface) {
		Graphics.drawRect(surface, trackColor, bounds);
		Rect thumb = getThumbRect();
		Color c = dragging || (hovered && thumb.contains(Point(instance.mouseX, instance.mouseY))) ? thumbHoverColor : thumbColor;
		Graphics.drawRect(surface, c, thumb);
	}
}

class ListView : GUIObject {
	dstring[] items;
	int selectedIndex = -1;
	int itemHeight = 30;
	Font font;
	Scrollbar scrollbar;
	void delegate(int index) onItemSelected;

	this(Rect bounds) {
		super();
		this.bounds = bounds;
		scrollbar = new Scrollbar(Rect(bounds.x + bounds.w - 15, bounds.y, 15, bounds.h));
	}

	override void setManager(GUIManager m) {
		super.setManager(m);
		if (scrollbar !is null) scrollbar.setManager(m);
	}

	void addItem(dstring item) {
		items ~= item;
		updateScrollbar();
	}

	private void updateScrollbar() {
		float totalHeight = items.length * itemHeight;
		if (totalHeight > bounds.h) {
			scrollbar.thumbSize = cast(float)bounds.h / totalHeight;
			scrollbar.enabled = true;
		} else {
			scrollbar.thumbSize = 1.0f;
			scrollbar.enabled = false;
			scrollbar.value = 0;
		}
	}

	override void update(float dt) {
		scrollbar.update(dt);

		scrollbar.bounds.x = bounds.x + bounds.w - 15;
		scrollbar.bounds.y = bounds.y;
		scrollbar.bounds.h = bounds.h;
	}

	override void collectFocusables(ref GUIObject[] list) {
		super.collectFocusables(list);
		if (scrollbar !is null) scrollbar.collectFocusables(list);
	}

	override bool handleInput(Event event) {
		if (scrollbar.enabled && scrollbar.handleInput(event)) return true;

		int mx = -1, my = -1;
		if (event.type == EventType.mouseMoved) {
			mx = event.mouseMoved.x;
			my = event.mouseMoved.y;
		} else if (event.type == EventType.mouseButtonPressed || event.type == EventType.mouseButtonReleased) {
			mx = event.mouse.x;
			my = event.mouse.y;
		}

		if (event.type == EventType.mouseWheel && bounds.contains(Point(instance.mouseX, instance.mouseY))) {
			if (scrollbar.enabled) {
				float totalHeight = items.length * itemHeight;
				float viewportHeight = bounds.h;
				float scrollStep = (itemHeight * 2.0f) / (totalHeight - viewportHeight);
				scrollbar.value -= event.mouseWheel.delta * scrollStep;
				return true;
			}
		}

		if (event.type == EventType.mouseButtonPressed && event.mouse.button == MouseEvent.ButtonType.left) {
			if (bounds.contains(Point(mx, my))) {
				float scrollOffset = scrollbar.value * (max(0.0f, items.length * itemHeight - bounds.h));
				int clickedIndex = cast(int)((my - bounds.y + scrollOffset) / itemHeight);
				if (clickedIndex >= 0 && clickedIndex < items.length) {
					selectedIndex = clickedIndex;
					if (onItemSelected !is null) onItemSelected(selectedIndex);
					return true;
				}
			}
		}

		return bounds.contains(Point(instance.mouseX, instance.mouseY));
	}

	private Surface[] _cachedItemSurfs;
	private dstring[] _lastItems;
	private Font _lastFont;

	override void draw(Surface surface) {
		Graphics.drawRect(surface, Color(20, 20, 25), bounds);
		
		surface.setClip(bounds);
		float scrollOffset = scrollbar.value * (max(0.0f, items.length * itemHeight - bounds.h));

		if (_lastItems != items || _lastFont !is font) {
			_cachedItemSurfs = new Surface[items.length];
            foreach(i, item; items) {
                if (font !is null)
                    _cachedItemSurfs[i] = font.getText(to!string(item), Colors.white, 20);
            }
            _lastItems = items.dup;
            _lastFont = font;
		}
		
        int startY = bounds.y - cast(int)scrollOffset;
        
        foreach(i, item; items) {
            int y = startY + (cast(int)i * itemHeight);
            if (y + itemHeight < bounds.y) continue;
            if (y > bounds.y + bounds.h) break;
            
            if (i == selectedIndex) {
                 Graphics.drawRect(surface, Color(50, 50, 80), Rect(bounds.x, y, bounds.w - 15, itemHeight));
            }
            
            if (i < _cachedItemSurfs.length && _cachedItemSurfs[i] !is null) {
                 surface.blit(_cachedItemSurfs[i], bounds.x + 5, y + (itemHeight - _cachedItemSurfs[i].height)/2);
            }
        }

		surface.resetClip();
        
        scrollbar.draw(surface);
	}
}

class Label : GUIObject {
    dstring text;
    Font font;
    Color color;
    int fontSize;
    bool centered = false;

    this(dstring text, Font font, int fontSize = 20, Color color = Colors.white) {
        super();
        this.text = text;
        this.font = font;
        this.fontSize = fontSize;
        this.color = color;
        this.focusable = false;
        
        if (font !is null) {
             Size sz = font.getSize(to!string(text), fontSize);
             this.bounds = Rect(0, 0, sz.w, sz.h);
        }
    }

    private Surface _cachedSurf;
    private dstring _lastText;

    override void draw(Surface dest) {
        if (font is null) return;
        
        if (_cachedSurf is null || text != _lastText) {
             _cachedSurf = font.getText(to!string(text), color, fontSize);
             _lastText = text;
             if (this.bounds.w == 0) { // Auto-size if not set manually
                this.bounds.w = _cachedSurf.width;
                this.bounds.h = _cachedSurf.height;
             }
        }
        
        int x = bounds.x;
        int y = bounds.y;
        
        if (centered) {
            x += (bounds.w - _cachedSurf.width) / 2;
            y += (bounds.h - _cachedSurf.height) / 2;
        }
        
        dest.blit(_cachedSurf, x, y);
    }
    
    override void update(float dt) {}
    override bool handleInput(Event e) { return false; }
}

class CheckBox : GUIObject {
    bool checked;
    dstring label;
    Font font;
    void delegate(bool) onChange;
    
    bool hovered = false;

    this(dstring label, bool initial, void delegate(bool) onChange = null) {
        super();
        this.label = label;
        this.checked = initial;
        this.onChange = onChange;
        this.focusable = true;
        this.bounds = Rect(0, 0, 200, 30);
    }

    override void update(float dt) {}
    
    override bool handleInput(Event e) {
        if (e.type == EventType.mouseMoved) {
            hovered = bounds.contains(Point(e.mouseMoved.x, e.mouseMoved.y));
        }
        else if (e.type == EventType.mouseButtonPressed && e.mouse.button == MouseEvent.ButtonType.left) {
            if (bounds.contains(Point(e.mouse.x, e.mouse.y))) {
                toggle();
                return true;
            }
        }
        return false;
    }
    
    void toggle() {
        checked = !checked;
        if (onChange !is null) onChange(checked);
    }

    override void draw(Surface dest) {
        int boxSize = 20;
        Rect boxRect = Rect(bounds.x, bounds.y + (bounds.h - boxSize)/2, boxSize, boxSize);
        
        Graphics.drawRect(dest, hovered ? Color(60, 60, 60) : Color(40, 40, 40), boxRect);
        Graphics.drawRect(dest, Colors.white, Rect(boxRect.x, boxRect.y, boxSize, 1));
        Graphics.drawRect(dest, Colors.white, Rect(boxRect.x, boxRect.y + boxSize - 1, boxSize, 1));
        Graphics.drawRect(dest, Colors.white, Rect(boxRect.x, boxRect.y, 1, boxSize));
        Graphics.drawRect(dest, Colors.white, Rect(boxRect.x + boxSize - 1, boxRect.y, 1, boxSize));
        
        if (checked) {
            Graphics.drawRect(dest, Colors.green, Rect(boxRect.x + 4, boxRect.y + 4, boxSize - 8, boxSize - 8));
        }
        
        if (font !is null && label.length > 0) {
            Surface textSurf = font.getText(to!string(label), Colors.white, 20);
            dest.blit(textSurf, bounds.x + boxSize + 10, bounds.y + (bounds.h - textSurf.height)/2);
        }
    }
}

class TabControl : GUIObject {
    struct Tab {
        dstring title;
        GUIObject content;
    }
    
    Tab[] tabs;
    int activeTab = 0;
    Font font;
    int headerHeight = 40;
    
    this(Rect bounds) {
        super();
        this.bounds = bounds;
    }
    
    void addTab(dstring title, GUIObject content) {
        tabs ~= Tab(title, content);
        if (content.manager is null && manager !is null) {
            content.setManager(manager);
        }
    }
    
    override void setManager(GUIManager m) {
        super.setManager(m);
        foreach(tab; tabs) {
            tab.content.setManager(m);
        }
    }
    
    override void update(float dt) {
        if (activeTab >= 0 && activeTab < tabs.length) {
            // Ensure content bounds match our client area
            Rect clientArea = Rect(bounds.x, bounds.y + headerHeight, bounds.w, bounds.h - headerHeight);
            GUIObject content = tabs[activeTab].content;
            
            if (content.bounds != clientArea) {
                 content.performLayout(clientArea);
            }
            
            content.update(dt);
        }
    }
    
    override void draw(Surface dest) {
        // Draw Header
        int tabWidth = 150;
        foreach(i, tab; tabs) {
             Rect tabRect = Rect(bounds.x + cast(int)i * tabWidth, bounds.y, tabWidth, headerHeight);
             bool isActive = (i == activeTab);
             
             Color bg = isActive ? Color(60, 60, 70) : Color(40, 40, 50);
             Graphics.drawRect(dest, bg, tabRect);
             Graphics.drawRect(dest, Color(80, 80, 90), Rect(tabRect.x, tabRect.y, tabRect.w, 1));
             Graphics.drawRect(dest, Color(80, 80, 90), Rect(tabRect.x + tabRect.w - 1, tabRect.y, 1, tabRect.h));
             
             if (font !is null) {
                 Surface titleSurf = font.getText(to!string(tab.title), isActive ? Colors.yellow : Colors.white, 16);
                 dest.blit(titleSurf, tabRect.x + (tabRect.w - titleSurf.width)/2, tabRect.y + (tabRect.h - titleSurf.height)/2);
             }
        }
        
        // Draw Content Border
        Rect contentRect = Rect(bounds.x, bounds.y + headerHeight, bounds.w, bounds.h - headerHeight);
        Graphics.drawRect(dest, Color(30,30,35), contentRect);
        
        if (activeTab >= 0 && activeTab < tabs.length) {
            tabs[activeTab].content.draw(dest);
        }
    }
    
    override bool handleInput(Event e) {
        // Check Header Clicks
        if (e.type == EventType.mouseButtonPressed && e.mouse.button == MouseEvent.ButtonType.left) {
             Point p = Point(e.mouse.x, e.mouse.y);
             if (p.y >= bounds.y && p.y < bounds.y + headerHeight && p.x >= bounds.x) {
                 int tabWidth = 150;
                 int idx = (p.x - bounds.x) / tabWidth;
                 if (idx >= 0 && idx < tabs.length) {
                     activeTab = idx;
                     return true;
                 }
             }
        }
        
        // Propagate to active content
        if (activeTab >= 0 && activeTab < tabs.length) {
             return tabs[activeTab].content.handleInput(e);
        }
        
        return false;
    }
    
    override void collectFocusables(ref GUIObject[] list) {
        if (activeTab >= 0 && activeTab < tabs.length) {
            tabs[activeTab].content.collectFocusables(list);
        }
    }



}

class GUIConsole : GUIWindow {
	this(dstring title, Rect bounds) {
		super(title, bounds);
	}
}

class FileDialog : GUIWindow {
	string currentPath;
	ListView fileList;
	TextInput pathInput;
	Button openButton;
	Button cancelButton;
	void delegate(string path) onFileSelected;
	bool showErrorOnNotFound = false;

	this(dstring title, Rect bounds, string initialPath = ".") {
		super(title, bounds);
		currentPath = absolutePath(initialPath);

		fileList = new ListView(Rect(bounds.x + 10, bounds.y + 40, bounds.w - 20, bounds.h - 120));
		fileList.onItemSelected = &onItemSelect;
		addChild(fileList);

		pathInput = new TextInput();
		pathInput.bounds = Rect(bounds.x + 10, bounds.y + bounds.h - 70, bounds.w - 20, 30);
		pathInput.text = currentPath.to!dstring;
		addChild(pathInput);

		openButton = new Button("Open"d, &onOpenClick);
		openButton.bounds = Rect(bounds.x + bounds.w - 180, bounds.y + bounds.h - 35, 80, 25);
		addChild(openButton);

		cancelButton = new Button("Cancel"d, &onCancelClick);
		cancelButton.bounds = Rect(bounds.x + bounds.w - 90, bounds.y + bounds.h - 35, 80, 25);
		addChild(cancelButton);

		this.refresh();
	}

	override void performLayout(Rect area) {
		super.performLayout(area);
		
		if (fileList !is null) {
			fileList.bounds = Rect(bounds.x + 10, bounds.y + 40, bounds.w - 20, bounds.h - 120);
			fileList.performLayout(fileList.bounds);
		}
		if (pathInput !is null) {
			pathInput.bounds = Rect(bounds.x + 10, bounds.y + bounds.h - 70, bounds.w - 20, 30);
			pathInput.performLayout(pathInput.bounds);
		}
		if (openButton !is null) {
			openButton.bounds = Rect(bounds.x + bounds.w - 180, bounds.y + bounds.h - 35, 80, 25);
			openButton.performLayout(openButton.bounds);
		}
		if (cancelButton !is null) {
			cancelButton.bounds = Rect(bounds.x + bounds.w - 90, bounds.y + bounds.h - 35, 80, 25);
			cancelButton.performLayout(cancelButton.bounds);
		}
	}

	void show(GUIManager manager) {
		this.setManager(manager);
		this.bounds.x = (manager.size.w - bounds.w) / 2;
		this.bounds.y = (manager.size.h - bounds.h) / 2;
		
		performLayout(bounds);

		this.visible = true;
		manager.addObject(this);
	}

	override void update(float dt) {
		super.update(dt);
		fileList.font = this.font;
		pathInput.font = this.font;
		openButton.font = this.font;
		cancelButton.font = this.font;
	}

	void refresh() {
		fileList.items = [];
		fileList.addItem(".."d);

		try {
			foreach (DirEntry entry; dirEntries(currentPath, SpanMode.shallow)) {
				dstring name = entry.name.baseName.to!dstring;
				if (entry.isDir) name ~= "/"d;
				fileList.addItem(name);
			}
		} catch (Exception e) {
		}
		pathInput.text = currentPath.to!dstring;
	}

	private void onItemSelect(int index) {
		dstring selected = fileList.items[index];
		if (selected == ".."d) {
			currentPath = currentPath.dirName;
			refresh();
		} else if (selected.endsWith("/"d)) {
			currentPath = buildPath(currentPath, selected[0 .. $-1].to!string);
			refresh();
		} else {
			pathInput.text = buildPath(currentPath, selected.to!string).to!dstring;
		}
	}

	protected void onOpenClick() {
		string selectedPath = pathInput.text.to!string;
		if (selectedPath.exists && !selectedPath.isDir) {
			if (onFileSelected !is null) onFileSelected(selectedPath);
			this.visible = false;
		} else if (selectedPath.exists && selectedPath.isDir) {
			currentPath = selectedPath;
			refresh();
		} else {
			if (showErrorOnNotFound) {
				auto mb = new GUIMessageBox("Error"d, "File not found: "d ~ selectedPath.to!dstring, GUIMessageBox.IconType.Error);
				mb.font = this.font;
				mb.show(this.manager);
			}
		}
	}

	private void onCancelClick() {
		this.visible = false;
		if (manager !is null) manager.removeObject(this);
	}
}

class FolderDialog : FileDialog {
	this(dstring title, Rect bounds, string initialPath = ".") {
		super(title, bounds, initialPath);
		pathInput.text = currentPath.to!dstring;
		openButton.text = "Select"d;
	}

	override void refresh() {
		fileList.items = [];
		fileList.addItem(".."d);

		try {
			foreach (DirEntry entry; dirEntries(currentPath, SpanMode.shallow)) {
				if (entry.isDir) {
					fileList.addItem(entry.name.baseName.to!dstring ~ "/"d);
				}
			}
		} catch (Exception e) {
		}
		pathInput.text = currentPath.to!dstring;
	}

	override protected void onOpenClick() {
		string selectedPath = pathInput.text.to!string;
		if (selectedPath.exists && selectedPath.isDir) {
			if (onFileSelected !is null) onFileSelected(selectedPath);
			this.visible = false;
			if (manager !is null) manager.removeObject(this);
		} else {
			if (showErrorOnNotFound) {
				auto mb = new GUIMessageBox("Error"d, "Folder not found: "d ~ selectedPath.to!dstring, GUIMessageBox.IconType.Error);
				mb.font = this.font;
				mb.show(this.manager);
			}
		}
	}
}

class GUIMessageBox : GUIWindow {
	enum IconType { Info, Error, Question }
	enum Buttons { OK, YesNo }
	enum Result { OK, Yes, No }
	
	dstring message;
	IconType iconType;
	Buttons buttonType;
	void delegate(Result result) onResult;
	
	private Button okButton;
	private Button yesButton;
	private Button noButton;
	private Scrollbar vScroll;
	private Scrollbar hScroll;
	private Size totalContentSize;
	
	this(dstring title, dstring message, IconType iconType = IconType.Info, Buttons buttonType = Buttons.OK) {
		super(title, Rect(0, 0, 400, 180));
		this.message = message;
		this.iconType = iconType;
		this.buttonType = buttonType;
		
		if (buttonType == Buttons.OK) {
			okButton = new Button("OK"d, { 
				if (onResult !is null) onResult(Result.OK);
				this.visible = false; 
				manager.removeObject(this);
			});
			addChild(okButton);
		} else if (buttonType == Buttons.YesNo) {
			yesButton = new Button("Yes"d, { 
				if (onResult !is null) onResult(Result.Yes);
				this.visible = false; 
				manager.removeObject(this);
			});
			addChild(yesButton);
			
			noButton = new Button("No"d, { 
				if (onResult !is null) onResult(Result.No);
				this.visible = false; 
				manager.removeObject(this);
			});
			addChild(noButton);
		}
		
		vScroll = new Scrollbar(Rect(0, 0, 15, 100));
		vScroll.visible = false;
		addChild(vScroll);
		
		hScroll = new Scrollbar(Rect(0, 0, 100, 15));
		hScroll.visible = false;
		addChild(hScroll);
	}
	
	void autoSize(GUIManager manager) {
		if (font is null) return;

		int screenW = cast(int)manager.size.w;
		int screenH = cast(int)manager.size.h;
		int maxW = cast(int)(screenW * 0.8);
		int maxH = cast(int)(screenH * 0.8);

		int textX = 80;
		int textY = 50;
		int bottomPadding = 70;
		
		string sMsg = to!string(message);
		int wrapW = 300;
		string[] lines = font.wrapText(sMsg, 16, wrapW);
		int totalH = cast(int)lines.length * 18;

		if (totalH + textY + bottomPadding > maxH && maxW > 400) {
			wrapW = maxW - textX - 40;
			lines = font.wrapText(sMsg, 16, wrapW);
			totalH = cast(int)lines.length * 18;
		}

		int contentW = 0;
		foreach(l; lines) {
			Size sz = font.getSize(l, 16);
			if (sz.w > contentW) contentW = sz.w;
		}

		int bestW = max(400, contentW + textX + 40);
		int bestH = max(180, totalH + textY + bottomPadding);

		if (bestW > maxW) bestW = maxW;
		if (bestH > maxH) {
			bestH = maxH;
		}

		this.bounds.w = bestW;
		this.bounds.h = bestH;
		this.totalContentSize = Size(contentW, totalH);
		
		if (totalH > bounds.h - textY - bottomPadding) {
			vScroll.visible = true;
			vScroll.thumbSize = cast(float)(bounds.h - textY - bottomPadding) / totalH;
		} else {
			vScroll.visible = false;
			vScroll.value = 0;
		}

		if (contentW > bounds.w - textX - 40) {
			hScroll.visible = true;
			hScroll.thumbSize = cast(float)(bounds.w - textX - 40) / contentW;
		} else {
			hScroll.visible = false;
			hScroll.value = 0;
		}
	}
	
	override void performLayout(Rect area) {
		super.performLayout(area);
		
		int textX = 80;
		int textY = 50;
		int bottomPadding = 70;

		if (vScroll !is null && vScroll.visible) {
			vScroll.bounds = Rect(bounds.x + bounds.w - 20, bounds.y + textY, 15, bounds.h - textY - bottomPadding);
			vScroll.performLayout(vScroll.bounds);
		}
		
		if (hScroll !is null && hScroll.visible) {
			hScroll.bounds = Rect(bounds.x + textX, bounds.y + bounds.h - bottomPadding + 5, bounds.w - textX - 25, 15);
			hScroll.performLayout(hScroll.bounds);
		}

		if (buttonType == Buttons.OK) {
			if (okButton !is null) {
				okButton.bounds = Rect(bounds.x + (bounds.w - 80) / 2, bounds.y + bounds.h - 50, 80, 30);
				okButton.performLayout(okButton.bounds);
			}
		} else {
			if (yesButton !is null) {
				yesButton.bounds = Rect(bounds.x + bounds.w / 2 - 90, bounds.y + bounds.h - 50, 80, 30);
				yesButton.performLayout(yesButton.bounds);
			}
			if (noButton !is null) {
				noButton.bounds = Rect(bounds.x + bounds.w / 2 + 10, bounds.y + bounds.h - 50, 80, 30);
				noButton.performLayout(noButton.bounds);
			}
		}
	}

	void show(GUIManager manager) {
		this.setManager(manager);
		autoSize(manager);
		this.bounds.x = (manager.size.w - bounds.w) / 2;
		this.bounds.y = (manager.size.h - bounds.h) / 2;
		
		performLayout(bounds);
		
		this.visible = true;
		manager.addObject(this);
	}

	override void update(float dt) {
		super.update(dt);
		if (vScroll !is null && vScroll.visible) vScroll.update(dt);
		if (hScroll !is null && hScroll.visible) hScroll.update(dt);
		if (buttonType == Buttons.OK) {
			if (okButton !is null) okButton.font = this.font;
		} else {
			if (yesButton !is null) yesButton.font = this.font;
			if (noButton !is null) noButton.font = this.font;
		}
	}

	override bool handleInput(Event event) {
		if (vScroll !is null && vScroll.visible && vScroll.handleInput(event)) return true;
		if (hScroll !is null && hScroll.visible && hScroll.handleInput(event)) return true;
		
		if (event.type == EventType.mouseWheel && vScroll !is null && vScroll.visible) {
			if (bounds.contains(Point(instance.mouseX, instance.mouseY))) {
				vScroll.value -= event.mouseWheel.delta * 0.1f;
				return true;
			}
		}
		
		return super.handleInput(event);
	}

	private Surface[] _cachedMsgLines;
	private dstring _lastMsg;
	private Font _lastFont;

	override void draw(Surface surface) {
		super.draw(surface);
		
		Color iconColor = Color(50, 120, 220);
		if (iconType == IconType.Error) iconColor = Color(220, 50, 50);
		else if (iconType == IconType.Question) iconColor = Color(220, 200, 50);

		Graphics.drawRect(surface, iconColor, Rect(bounds.x + 20, bounds.y + 50, 40, 40));
		
		if (font !is null) {
			string iconChar = "i";
			if (iconType == IconType.Error) iconChar = "!";
			else if (iconType == IconType.Question) iconChar = "?";
			Surface iconSurf = font.getText(iconChar, Colors.white, 32);
			surface.blit(iconSurf, bounds.x + 20 + (40 - iconSurf.width) / 2, bounds.y + 50 + (40 - iconSurf.height) / 2);
			
			int textX = 80;
			int textY = 50;
			int bottomPadding = 70;
			Rect textArea = Rect(bounds.x + textX, bounds.y + textY, bounds.w - textX - 25, bounds.h - textY - bottomPadding);

			if (message != _lastMsg || font !is _lastFont || _cachedMsgLines is null) {
				string[] wrapped = font.wrapText(to!string(message), 16, textArea.w);
				_cachedMsgLines = new Surface[wrapped.length];
				foreach (i, line; wrapped) {
					_cachedMsgLines[i] = font.getText(line, Colors.white, 16);
				}
				_lastMsg = message;
				_lastFont = font;
			}

			surface.setClip(textArea);
			
			int scrollX = 0;
			if (hScroll !is null && hScroll.visible) {
				scrollX = cast(int)(hScroll.value * (totalContentSize.w - textArea.w));
			}

			int scrollY = 0;
			if (vScroll !is null && vScroll.visible) {
				scrollY = cast(int)(vScroll.value * (totalContentSize.h - textArea.h));
			}

			int ty = textArea.y - scrollY;
			if (_cachedMsgLines.length == 1 && !vScroll.visible) {
				ty += (textArea.h - _cachedMsgLines[0].height) / 2;
			}

			foreach (lineSurf; _cachedMsgLines) {
				surface.blit(lineSurf, textArea.x - scrollX, ty);
				ty += lineSurf.height + 2;
			}
			
			surface.resetClip();
		}
		
		if (vScroll !is null && vScroll.visible) vScroll.draw(surface);
		if (hScroll !is null && hScroll.visible) hScroll.draw(surface);
	}
}
