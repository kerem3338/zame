module zame.core.fs.providers.zip;

import zame.core.fs.provider;
import zame.core.fs.stream;
import zame.core.fs.path;
import zame.core.fs.entry : FsItem, FsItemType;
import zame.core.common;
import zame.core.fs.providers.memory;

import std.zip;
import std.file : read;
import std.exception : collectException;
import std.datetime.systime : SysTime;
import std.datetime.date : DateTime;
import std.string : indexOf, replace;

class ZipProvider : IFsProvider {
    private ZipArchive archive;
    private string archivePath;
    private ArchiveMember[string] normalizedEntries;

    this(string archivePath) {
        this.archivePath = archivePath;
        try {
            auto data = read(archivePath);
            archive = new ZipArchive(data);
            foreach (k, v; archive.directory) {
                string normKey = cleanKey(k);
                normalizedEntries[normKey] = v;
            }
        } catch (Exception e) {
            archive = null;
        }
    }

    override @property string name() const {
        return "ZipProvider";
    }

    override string getPhysicalPath(FsPath path) {
        return null;
    }

    private string cleanKey(string key) const {
        string k = key.replace("\\", "/");
        while (k.length > 0 && k[0] == '/') k = k[1 .. $];
        while (k.length > 0 && k[$ - 1] == '/') k = k[0 .. $ - 1];
        return k;
    }

    override Outcome!IStream open(FsPath path, VfsOpenMode mode = VfsOpenMode.read) {
        bool forWriting = (mode & VfsOpenMode.write) != 0 || (mode & VfsOpenMode.append) != 0 || (mode & VfsOpenMode.readWrite) != 0;
        if (forWriting) {
            return failure!IStream(Result.unknown_error, "ZipProvider is read-only");
        }
        if (archive is null) {
            return failure!IStream(Result.unknown_error, "Zip archive not loaded");
        }
        
        string key = cleanKey(path.relativePath);
        auto am = key in normalizedEntries;
        if (!am) {
            return failure!IStream(Result.file_not_found, "File not found in zip");
        }
        
        try {
            auto uncompressedData = archive.expand(*am);
            return success!IStream(new MemoryStream(null, key, uncompressedData, VfsOpenMode.read));
        } catch (Exception e) {
            return failure!IStream(Result.unknown_error, e.msg);
        }
    }

    override Outcome!ulong size(FsPath path) {
        if (archive is null) return failure!ulong(Result.file_not_found, "Archive not loaded");
        string key = cleanKey(path.relativePath);
        if (key.length == 0 || isDirectory(path)) return success!ulong(0);
        if (auto am = key in normalizedEntries) {
            return success!ulong(am.expandedSize);
        }
        return failure!ulong(Result.file_not_found, "File not found");
    }

    override bool exists(FsPath path) {
        if (archive is null) return false;
        string key = cleanKey(path.relativePath);
        if (key.length == 0) return true; // root exists
        return (key in normalizedEntries) !is null || isDirectory(path);
    }

    override bool isDirectory(FsPath path) {
        if (archive is null) return false;
        string key = cleanKey(path.relativePath);
        if (key.length == 0) return true; // root is directory
        string prefix = key ~ "/";
        foreach (k; normalizedEntries.keys) {
            if (k.length > prefix.length && k[0 .. prefix.length] == prefix) {
                return true;
            }
        }
        return false;
    }
    
    override Outcome!SysTime modifiedTime(FsPath path) {
        if (archive is null) return failure!SysTime(Result.file_not_found, "Archive not loaded");
        string key = cleanKey(path.relativePath);
        if (key.length == 0) {
            import std.datetime.systime : Clock;
            return success!SysTime(Clock.currTime());
        }
        if (auto am = key in normalizedEntries) {
            uint t = am.time;
            int year = (t >> 25) + 1980;
            int month = (t >> 21) & 0x0f;
            int day = (t >> 16) & 0x1f;
            int hour = (t >> 11) & 0x1f;
            int min = (t >> 5) & 0x3f;
            int sec = (t & 0x1f) * 2;
            if (month == 0) month = 1;
            if (day == 0) day = 1;
            try {
                return success!SysTime(SysTime(DateTime(year, month, day, hour, min, sec)));
            } catch (Exception e) {
                return failure!SysTime(Result.unknown_error, e.msg);
            }
        }
        if (isDirectory(path)) {
            import std.datetime.systime : Clock;
            return success!SysTime(Clock.currTime());
        }
        return failure!SysTime(Result.file_not_found, "File not found");
    }
    
    override Outcome!(FsItem[]) listDirectory(FsPath path) {
        if (archive is null) return failure!(FsItem[])(Result.file_not_found, "Archive not loaded");
        
        string key = cleanKey(path.relativePath);
        string prefix = key.length > 0 ? key ~ "/" : "";
        bool[string] uniqueNames;
        
        foreach (k; normalizedEntries.keys) {
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
        foreach (k, isDir; uniqueNames) {
            FsItem item;
            item.name = k;
            item.exists = true;
            item.type = isDir ? FsItemType.directory : FsItemType.file;
            if (!isDir) {
                string fullKey = prefix ~ k;
                if (auto am = fullKey in normalizedEntries) {
                    item.size = am.expandedSize;
                    uint t = am.time;
                    int year = (t >> 25) + 1980;
                    int month = (t >> 21) & 0x0f;
                    int day = (t >> 16) & 0x1f;
                    int hour = (t >> 11) & 0x1f;
                    int min = (t >> 5) & 0x3f;
                    int sec = (t & 0x1f) * 2;
                    if (month == 0) month = 1;
                    if (day == 0) day = 1;
                    try { item.modifiedTime = SysTime(DateTime(year, month, day, hour, min, sec)); } catch (Exception) {}
                }
            }
            result ~= item;
        }
        return success!(FsItem[])(result);
    }

    override ResultStatus mkdir(FsPath path, bool recursive = false) {
        return ResultStatus(Result.unknown_error, "ZipProvider is read-only");
    }

    override ResultStatus remove(FsPath path) {
        return ResultStatus(Result.unknown_error, "ZipProvider is read-only");
    }

    override ResultStatus rename(FsPath src, string newName) {
        return ResultStatus(Result.unknown_error, "ZipProvider is read-only");
    }
}
