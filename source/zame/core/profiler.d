module zame.core.profiler;

import std.datetime.stopwatch;
import std.stdio;
import std.algorithm;
import std.array;
import std.format;
import core.sync.mutex;

struct ProfileResult {
    string name;
    ulong calls;
    Duration totalTime;
}

class Profiler {
    private static Profiler _instance;
    private ProfileResult[string] results;
    private Mutex mutex;

    private this() {
        mutex = new Mutex();
    }

    static Profiler instance() {
        if (_instance is null) {
            _instance = new Profiler();
        }
        return _instance;
    }

    void addResult(string name, Duration time) {
        mutex.lock();
        scope(exit) mutex.unlock();

        if (name !in results) {
            results[name] = ProfileResult(name, 0, Duration.zero);
        }
        
        results[name].calls++;
        results[name].totalTime += time;
    }

    void printResults() {
        mutex.lock();
        scope(exit) mutex.unlock();

        if (results.length == 0) return;

        writeln("--- Profiler Results ---");
        writeln(format("%-30s | %10s | %15s | %15s", "Name", "Calls", "Total Time", "Avg Time"));
        writeln("---------------------------------------------------------------------------");

        auto sortedKeys = results.keys;
        sort!((a, b) => results[a].totalTime > results[b].totalTime)(sortedKeys);

        foreach (name; sortedKeys) {
            auto res = results[name];
            auto avg = res.calls > 0 ? res.totalTime / res.calls : Duration.zero;
            writeln(format("%-30s | %10d | %15s | %15s", 
                name, res.calls, res.totalTime, avg));
        }
        writeln("------------------------");
    }

    void reset() {
        mutex.lock();
        scope(exit) mutex.unlock();
        results.clear();
    }
}

struct ScopedProfile {
    private string name;
    private StopWatch sw;

    this(string name) {
        this.name = name;
        this.sw = StopWatch(AutoStart.yes);
    }

    ~this() {
        sw.stop();
        Profiler.instance.addResult(name, sw.peek());
    }
}
