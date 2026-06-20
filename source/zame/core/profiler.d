module zame.core.profiler;

import std.datetime.stopwatch;
import zame.core.common;
import zame.core.graphics;
import zame.core.font;
import std.format;
import std.conv;
import std.stdio;
import std.algorithm.comparison : max, min;
import core.memory : GC;

/**
 * Pure Data Collector for Performance Metrics.
 * Focused only on recording and calculating statistics.
 */
class Profiler {
    static struct Section {
        string name;
        StopWatch sw;
        long lastDurationTicks;
        float averageMs = 0;
        float maxMs = 0;
    }

    private Section[] _sections;
    private float _fps = 0.0f;
    private float _frameTimeAvg = 0.0f;
    private long _frameCount = 0;

    this() {}

    const(Section[]) sections() const { return _sections; }
    float fps() const { return _fps; }
    float frameTimeAvg() const { return _frameTimeAvg; }
    long frameCount() const { return _frameCount; }

    void beginSection(string name) {
        foreach (ref s; _sections) {
            if (s.name == name) {
                s.sw.reset();
                s.sw.start();
                return;
            }
        }
        Section s;
        s.name = name;
        s.sw.start();
        _sections ~= s;
    }

    void endSection(string name) {
        foreach (ref s; _sections) {
            if (s.name == name) {
                s.sw.stop();
                float currentMs = cast(float)s.sw.peek().total!"hnsecs" / 10000.0f;
                
                s.averageMs = s.averageMs * 0.98f + currentMs * 0.02f;
                if (currentMs > s.maxMs) s.maxMs = currentMs;
                return;
            }
        }
    }

    void update(float dt) {
        _frameCount++;

        if (dt > 0) {
            float currentFps = 1.0f / dt;
            if (_fps == 0) _fps = currentFps;
            else _fps = _fps * 0.98f + currentFps * 0.02f;
            
            float currentMs = dt * 1000.0f;
            if (_frameTimeAvg == 0) _frameTimeAvg = currentMs;
            else _frameTimeAvg = _frameTimeAvg * 0.98f + currentMs * 0.02f;
        }
    }

    ProfileScope section(string name) {
        return ProfileScope(this, name);
    }
}

/**
 * RAII helper for balancing beginSection/endSection calls.
 */
struct ProfileScope {
    private Profiler _p;
    private string _name;

    @disable this();
    this(Profiler p, string name) {
        _p = p;
        _name = name;
        if (_p !is null) _p.beginSection(_name);
    }

    ~this() {
        if (_p !is null) _p.endSection(_name);
    }
}

/**
 * Base interface for objects that process and display Profiler results.
 */
interface IProfilerHandler {
    void handle(Profiler profiler);
}

/**
 * Renders Profiler results as a visual overlay on a Surface.
 */
class SurfaceProfilerHandler : IProfilerHandler {
    public bool visible = false;
    private Surface _surface;
    private Font _font;

    this(Surface surface, Font font) {
        _surface = surface;
        _font = font;
    }

    void handle(Profiler profiler) {
        if (!visible || profiler is null || _surface is null || _font is null) return;

        int w = 240;
        int h = 50 + (cast(int)profiler.sections.length * 20);
        int x = _surface.width - w - 10;
        int y = 50; 

        Graphics.drawRect(_surface, Color(0, 0, 0, 180), Rect(x, y, w, h));
        Graphics.drawRect(_surface, Colors.yellow, Rect(x, y, w, 1));
        
        string title = format("FPS: %.1f (%.2f ms)", profiler.fps, profiler.frameTimeAvg);
        _surface.blit(_font.getText(title, Colors.yellow, 16), x + 10, y + 8);

        foreach (i, s; profiler.sections) {
            string text = format("%-10s: %5.2fms | %5.2fm", s.name, s.averageMs, s.maxMs);
            _surface.blit(_font.getText(text, Colors.white, 13), x + 10, y + 32 + cast(int)i * 20);
        }
    }
}

/**
 * Prints Profiler results to the system console.
 */
class ConsoleProfilerHandler : IProfilerHandler {
    public bool enabled = false;
    private float _timer = 0.0f;
    private float _interval = 1.0f;

    this(float interval = 1.0f) {
        _interval = interval;
    }

    void update(float dt) {
        _timer += dt;
    }

    void handle(Profiler profiler) {
        if (!enabled || profiler is null) return;
        
        if (_timer >= _interval) {
            _timer = 0;
            print(profiler);
        }
    }

    private void print(Profiler profiler) {
        writefln("\n=== Zame Profiler [Frame: %d] ===", profiler.frameCount);
        writefln("Performance: %6.1f FPS | %6.2f ms", profiler.fps, profiler.frameTimeAvg);
        
        auto stats = GC.stats();
        writefln("Memory Usage: Used: %6.2f MB | Reserved: %6.2f MB", 
            cast(float)stats.usedSize / (1024*1024), 
            cast(float)stats.freeSize / (1024*1024));
        
        writefln("%-15s | %-10s | %-10s", "Section", "Avg Ms", "Peak Ms");
        writefln("---------------------------------------------");
        foreach (s; profiler.sections) {
            writefln("%-15s | %10.2f | %10.2f", s.name, s.averageMs, s.maxMs);
        }
        writefln("=============================================\n");
    }
}
