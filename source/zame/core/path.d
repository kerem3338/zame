module zame.core.path;

import std.file;
import std.path;
import std.algorithm;
import zame.core.cache;

enum PathEntryType {
    unknown,
    directory,
    file,
    notExists
}

struct PathEntry {
    string location;
    PathEntryType type = PathEntryType.unknown;
    string[] tags;

    this(string location, string[] tags = null) {
        this.location = location;
        this.tags = tags;
        this.type = determineEntryType();
    }

    PathEntryType determineEntryType() const {
        if (location.exists) {
            if (location.isDir) return PathEntryType.directory;
            if (location.isFile) return PathEntryType.file;
            return PathEntryType.unknown;
        }
        return PathEntryType.notExists;
    }
}

class PathManager : ConfigManager {
    private CacheManager _cache;

    this() {
        super();
        _cache = new CacheManager();
    }

    void setPath(string name, string location, string[] tags = null, ConfigValueFlags flags = ConfigValueFlags.none) {
        string absLoc = location.absolutePath;
        PathEntry entry = PathEntry(absLoc, tags);
        super.set!PathEntry(name, entry, flags);
    }

    void removePath(string name) {
        super.remove(name);
    }

    string getPath(string name) {
        auto entry = getPathEntry(name);
        return entry.location;
    }

    PathEntry getPathEntry(string name) {
        if (has(name)) {
            PathEntry entry = super.get!PathEntry(name);
            entry.type = entry.determineEntryType();
            return entry;
        }
        return PathEntry.init;
    }

    string[] getPathsByTag(string tag) {
        string[] result;
        foreach (key; configKeys()) {
            if (has(key)) {
                PathEntry entry = super.get!PathEntry(key);
                if (entry.tags.canFind(tag)) {
                    result ~= key;
                }
            }
        }
        return result;
    }

    string resolve(string baseName, string relativePath) {
        string base = getPath(baseName);
        if (base is null) return null;
        return buildPath(base, relativePath);
    }

    string resolveFirst(string[] names, string relativePath) {
        foreach (name; names) {
            string full = resolve(name, relativePath);
            if (full !is null && full.exists)
                return full;
        }
        return null;
    }

    string findFile(string filename, string[] searchPaths = null) {
        string[] keysToSearch;
        if (searchPaths is null || searchPaths.length == 0) {
            keysToSearch = configKeys();
        } else {
            keysToSearch = searchPaths;
        }

        foreach (key; keysToSearch) {
            string full = resolve(key, filename);
            if (full !is null && full.exists && full.isFile) {
                return full;
            }
        }
        return null;
    }

    string[] findAllFiles(string filename, string[] searchPaths = null) {
        string[] results;
        string[] keysToSearch;
        if (searchPaths is null || searchPaths.length == 0) {
            keysToSearch = configKeys();
        } else {
            keysToSearch = searchPaths;
        }

        foreach (key; keysToSearch) {
            string full = resolve(key, filename);
            if (full !is null && full.exists && full.isFile) {
                results ~= full;
            }
        }
        return results;
    }

    PathEntryType getType(string fullPath) {
        if (!fullPath.exists) return PathEntryType.notExists;
        if (fullPath.isDir) return PathEntryType.directory;
        if (fullPath.isFile) return PathEntryType.file;
        return PathEntryType.unknown;
    }

    bool exists(string fullPath) {
        return fullPath.exists;
    }

    string normalize(string path) {
        return path.absolutePath;
    }

    PathEntry opIndex(string name) {
        auto entry = getPathEntry(name);
        if (entry.location is null) throw new Exception("Path not found: " ~ name);
        return entry;
    }

    string[] listPathNames() {
        return configKeys();
    }
}