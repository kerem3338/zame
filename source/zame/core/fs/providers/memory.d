module zame.core.fs.providers.memory;

import zame.core.fs.provider;
import zame.core.fs.stream;
import zame.core.fs.path;
import zame.core.fs.entry : FsItem, FsItemType;
import zame.core.common;
import std.algorithm : min;
import std.datetime.systime : SysTime, Clock;
import std.string : indexOf, replace;

class MemoryStream : IStream {
    private ubyte[] data;
    private ulong pos;
    private bool open;
    private bool forWriting;
    private MemoryProvider owner;
    private string pathKey;

    this(MemoryProvider owner, string pathKey, ubyte[] existingData, VfsOpenMode mode) {
        this.owner = owner;
        this.pathKey = pathKey;
        this.data = existingData;
        this.pos = 0;
        this.open = true;
        this.forWriting = (mode & VfsOpenMode.write) != 0 || (mode & VfsOpenMode.append) != 0 || (mode & VfsOpenMode.readWrite) != 0;
        if ((mode & VfsOpenMode.append) != 0) {
            this.pos = this.data.length;
        }
    }
    
    ~this() {
        if (open) close();
    }

    override ulong length() {
        return data.length;
    }

    override ulong position() {
        return pos;
    }

    override bool seek(long offset, SeekOrigin origin = SeekOrigin.begin) {
        long newPos = 0;
        final switch(origin) {
            case SeekOrigin.begin: newPos = offset; break;
            case SeekOrigin.current: newPos = pos + offset; break;
            case SeekOrigin.end: newPos = data.length + offset; break;
        }
        if (newPos < 0) return false;
        if (newPos > data.length) return false;
        pos = newPos;
        return true;
    }

    override Outcome!size_t read(ubyte[] buffer) {
        if (!open) return failure!size_t(Result.unknown_error, "Stream is closed");
        
        size_t available = data.length - cast(size_t)pos;
        size_t toRead = min(buffer.length, available);
        
        if (toRead > 0) {
            buffer[0 .. toRead] = data[cast(size_t)pos .. cast(size_t)pos + toRead];
            pos += toRead;
        }
        
        return success!size_t(toRead);
    }

    override Outcome!size_t write(const(ubyte)[] buffer) {
        if (!open || !forWriting) return failure!size_t(Result.unknown_error, "Stream not opened for writing");
        
        size_t requiredLength = cast(size_t)pos + buffer.length;
        if (requiredLength > data.length) {
            data.length = requiredLength;
        }
        
        data[cast(size_t)pos .. cast(size_t)pos + buffer.length] = buffer[];
        pos += buffer.length;
        
        return success!size_t(buffer.length);
    }

    override void close() {
        if (open) {
            if (forWriting && owner !is null) {
                owner.saveFile(pathKey, data);
            }
            open = false;
        }
    }

    override bool isOpen() {
        return open;
    }
}

class MemoryProvider : IFsProvider {
    private ubyte[][string] files;
    private SysTime[string] times;

    override @property string name() const {
        return "MemoryProvider";
    }

    override string getPhysicalPath(FsPath path) {
        return null;
    }

    private string cleanKey(string key) const {
        string k = normalizeVfsPath(key);
        while (k.length > 0 && k[0] == '/') k = k[1 .. $];
        while (k.length > 0 && k[$ - 1] == '/') k = k[0 .. $ - 1];
        return k;
    }

    void saveFile(string path, ubyte[] data) {
        string k = cleanKey(path);
        files[k] = data.dup;
        times[k] = Clock.currTime();
    }

    void saveText(string path, string text) {
        saveFile(path, cast(ubyte[])text);
    }

    override Outcome!IStream open(FsPath path, VfsOpenMode mode = VfsOpenMode.read) {
        string key = cleanKey(path.relativePath);
        
        bool forWriting = (mode & VfsOpenMode.write) != 0 || (mode & VfsOpenMode.append) != 0 || (mode & VfsOpenMode.readWrite) != 0;
        
        if (forWriting) {
            ubyte[] data = (key in files) ? files[key].dup : [];
            return success!IStream(new MemoryStream(this, key, data, mode));
        } else {
            if (auto pData = key in files) {
                return success!IStream(new MemoryStream(this, key, (*pData).dup, mode));
            }
            return failure!IStream(Result.file_not_found, "File not found in memory");
        }
    }

    override Outcome!ulong size(FsPath path) {
        string key = cleanKey(path.relativePath);
        if (key.length == 0) {
            return success!ulong(0);
        }
        if (auto pData = key in files) {
            return success!ulong(pData.length);
        }
        if (isDirectory(path)) {
            return success!ulong(0);
        }
        return failure!ulong(Result.file_not_found, "File not found");
    }

    override bool exists(FsPath path) {
        string key = cleanKey(path.relativePath);
        if (key.length == 0) return true; // root always exists
        return (key in files) !is null || isDirectory(path);
    }

    override bool isDirectory(FsPath path) {
        string key = cleanKey(path.relativePath);
        if (key.length == 0) return true; // root is always a directory
        string prefix = key ~ "/";
        foreach (k; files.keys) {
            if (k.length > prefix.length && k[0 .. prefix.length] == prefix) return true;
            if (k == prefix) return true;
        }
        return false;
    }
    
    override Outcome!SysTime modifiedTime(FsPath path) {
        string key = cleanKey(path.relativePath);
        if (key.length == 0) {
            return success!SysTime(Clock.currTime());
        }
        if (auto pTime = key in times) {
            return success!SysTime(*pTime);
        }
        if (isDirectory(path)) {
            return success!SysTime(Clock.currTime());
        }
        return failure!SysTime(Result.file_not_found, "File not found");
    }
    
    override Outcome!(FsItem[]) listDirectory(FsPath path) {
        string key = cleanKey(path.relativePath);
        string prefix = key.length > 0 ? key ~ "/" : "";
        bool[string] uniqueNames;
        
        foreach (k; files.keys) {
            if (k.length >= prefix.length && (prefix.length == 0 || k[0 .. prefix.length] == prefix)) {
                string remainder = k[prefix.length .. $];
                if (remainder.length == 0) continue;
                auto slashIdx = indexOf(remainder, '/');
                if (slashIdx != -1) {
                    uniqueNames[remainder[0 .. slashIdx]] = true;
                } else {
                    uniqueNames[remainder] = false;
                }
            }
        }
        
        FsItem[] result;
        foreach(k, isDir; uniqueNames) {
            FsItem item;
            item.name = k;
            item.exists = true;
            item.type = isDir ? FsItemType.directory : FsItemType.file;
            if (!isDir) {
                string fullKey = prefix ~ k;
                if (auto pData = fullKey in files) {
                    item.size = pData.length;
                }
                if (auto pTime = fullKey in times) {
                    item.modifiedTime = *pTime;
                }
            }
            result ~= item;
        }
        return success!(FsItem[])(result);
    }

    override ResultStatus mkdir(FsPath path, bool recursive = false) {
        string key = cleanKey(path.relativePath);
        if (key.length > 0) {
            string dirPath = key ~ "/";
            if ((dirPath in files) is null) {
                files[dirPath] = [];
                times[dirPath] = Clock.currTime();
            }
        }
        return ResultStatus(Result.ok);
    }

    override ResultStatus remove(FsPath path) {
        string key = cleanKey(path.relativePath);
        if (key.length == 0) {
            return ResultStatus(Result.unknown_error, "Cannot remove root");
        }
        string prefix = key ~ "/";
        bool removed = false;
        
        if (key in files) {
            files.remove(key);
            times.remove(key);
            removed = true;
        }
        
        string[] toRemove;
        foreach (k; files.keys) {
            if (k.length >= prefix.length && k[0 .. prefix.length] == prefix) {
                toRemove ~= k;
            }
        }
        foreach(k; toRemove) {
            files.remove(k);
            times.remove(k);
            removed = true;
        }
        
        if (removed) return ResultStatus(Result.ok);
        return ResultStatus(Result.file_not_found, "File or directory not found");
    }

    override ResultStatus rename(FsPath src, string newName) {
        string srcKey = cleanKey(src.relativePath);
        if ((srcKey in files) is null) {
            return ResultStatus(Result.file_not_found, "Source not found");
        }
        
        import std.path : dirName;
        string dir = dirName(srcKey);
        string newPath = (dir == "." || dir == "") ? newName : dir ~ "/" ~ newName;
        newPath = cleanKey(newPath);
        
        files[newPath] = files[srcKey];
        times[newPath] = times[srcKey];
        files.remove(srcKey);
        times.remove(srcKey);
        
        return ResultStatus(Result.ok);
    }
}
