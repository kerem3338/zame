module zame.core.fs.entry;

import std.datetime.systime : SysTime;
import std.format : format;
import std.path : baseName, dirName, extension;

import zame.core.common;
import zame.core.fs.path;
import zame.core.fs.filesystem;
import zame.core.fs.stream;

enum FsItemType {
    unknown,
    file,
    directory,
    symlink,
    device
}

enum FsItemFlags : uint {
    none = 0,
    readOnly = 1 << 0,
    hidden = 1 << 1,
    system = 1 << 2
}

struct FsItem {
    string name;
    ulong size;
    FsItemType type;
    FsItemFlags flags;
    SysTime modifiedTime;
    bool exists;

    string toString() const {
        if (!exists) return "FsItem(not exists)";
        return format("FsItem(name: %s, type: %s, size: %d, modified: %s, flags: %d)", name, type, size, modifiedTime.toString(), flags);
    }
}

class VfsEntry {
    private VirtualFileSystem vfs;
    private string originalPath;
    private FsPath resolvedPath;
    private FsItem cachedInfo;
    private bool infoLoaded = false;

    this(VirtualFileSystem vfs, string path) {
        this.vfs = vfs;
        this.originalPath = path;
    }
    
    void refresh() {
        infoLoaded = false;
        loadInfo();
    }

    void loadInfo() {
        if (!infoLoaded) {
            resolvedPath = vfs.resolve(originalPath);
            if (resolvedPath.provider) {
                cachedInfo.exists = resolvedPath.provider.exists(resolvedPath);
                if (cachedInfo.exists) {
                    auto sizeRes = resolvedPath.provider.size(resolvedPath);
                    if (sizeRes.ok) cachedInfo.size = sizeRes.value;
                    
                    bool isDir = resolvedPath.provider.isDirectory(resolvedPath);
                    cachedInfo.type = isDir ? FsItemType.directory : FsItemType.file;
                    cachedInfo.flags = FsItemFlags.none;
                    
                    auto modTimeRes = resolvedPath.provider.modifiedTime(resolvedPath);
                    if (modTimeRes.ok) cachedInfo.modifiedTime = modTimeRes.value;
                }
            }
            infoLoaded = true;
        }
    }

    @property string fullPath() const {
        return originalPath;
    }

    @property FsPath path() {
        if (!infoLoaded) loadInfo();
        return resolvedPath;
    }

    @property string name() {
        if (!infoLoaded) loadInfo();
        return resolvedPath.baseName();
    }

    @property string baseName() {
        if (!infoLoaded) loadInfo();
        return resolvedPath.baseName();
    }

    @property string dirName() {
        if (!infoLoaded) loadInfo();
        return resolvedPath.dirName();
    }

    @property string extension() {
        if (!infoLoaded) loadInfo();
        return resolvedPath.extension();
    }

    @property string physicalPath() {
        if (!infoLoaded) loadInfo();
        return resolvedPath.physicalPath();
    }

    @property bool exists() {
        if (!infoLoaded) loadInfo();
        return cachedInfo.exists;
    }

    @property Outcome!ulong size() {
        if (!infoLoaded) loadInfo();
        if (cachedInfo.exists) return success!ulong(cachedInfo.size);
        return failure!ulong(Result.file_not_found, "File not found");
    }

    @property bool isDirectory() {
        if (!infoLoaded) loadInfo();
        return cachedInfo.type == FsItemType.directory;
    }

    @property bool isFile() {
        if (!infoLoaded) loadInfo();
        return cachedInfo.exists && cachedInfo.type != FsItemType.directory;
    }
    
    @property FsItemType type() {
        if (!infoLoaded) loadInfo();
        return cachedInfo.type;
    }

    @property FsItemFlags flags() {
        if (!infoLoaded) loadInfo();
        return cachedInfo.flags;
    }
    
    @property Outcome!SysTime modifiedTime() {
        if (!infoLoaded) loadInfo();
        if (cachedInfo.exists) return success!SysTime(cachedInfo.modifiedTime);
        return failure!SysTime(Result.file_not_found, "File not found");
    }

    VfsEntry child(string subpath) {
        return new VfsEntry(vfs, joinVfsPath(originalPath, subpath));
    }

    VfsEntry parent() {
        auto p = path();
        string d = p.dirName();
        if (p.uri.scheme.length > 0) {
            return new VfsEntry(vfs, p.uri.scheme ~ "://" ~ d);
        }
        return new VfsEntry(vfs, d.length > 0 ? d : ".");
    }

    VfsEntry opBinary(string op : "/")(string subpath) {
        return child(subpath);
    }

    VfsEntry opBinary(string op : "~")(string subpath) {
        return child(subpath);
    }

    Outcome!string readText() {
        return vfs.readText(originalPath);
    }

    Outcome!(ubyte[]) readAllBytes() {
        return vfs.readAllBytes(originalPath);
    }

    ResultStatus writeText(string content) {
        auto res = vfs.writeText(originalPath, content);
        if (res.ok) refresh();
        return res;
    }

    ResultStatus writeAllBytes(const(ubyte)[] data) {
        auto res = vfs.writeAllBytes(originalPath, data);
        if (res.ok) refresh();
        return res;
    }

    ResultStatus appendText(string content) {
        auto res = vfs.appendText(originalPath, content);
        if (res.ok) refresh();
        return res;
    }

    ResultStatus appendBytes(const(ubyte)[] data) {
        auto res = vfs.appendBytes(originalPath, data);
        if (res.ok) refresh();
        return res;
    }

    ResultStatus mkdir(bool recursive = true) {
        auto res = vfs.mkdir(originalPath, recursive);
        if (res.ok) refresh();
        return res;
    }

    ResultStatus remove() {
        auto res = vfs.remove(originalPath);
        if (res.ok) refresh();
        return res;
    }

    ResultStatus rename(string newName) {
        auto res = vfs.rename(originalPath, newName);
        if (res.ok) {
            originalPath = joinVfsPath(parent().fullPath, newName);
            refresh();
        }
        return res;
    }
    
    Outcome!(FsItem[]) listDirectory() {
        if (!infoLoaded) loadInfo();
        if (cachedInfo.type == FsItemType.directory && resolvedPath.provider) {
            return resolvedPath.provider.listDirectory(resolvedPath);
        }
        return failure!(FsItem[])(Result.unknown_error, "Not a directory or provider missing");
    }

    Outcome!(VfsEntry[]) listEntries() {
        auto itemsRes = listDirectory();
        if (!itemsRes.ok) return failure!(VfsEntry[])(itemsRes.status);
        VfsEntry[] entries;
        foreach (item; itemsRes.value) {
            entries ~= child(item.name);
        }
        return success!(VfsEntry[])(entries);
    }

    Outcome!(VfsEntry[]) findEntries(string pattern = "*", bool recursive = false) {
        auto filesRes = vfs.findFiles(originalPath, pattern, recursive);
        if (!filesRes.ok) return failure!(VfsEntry[])(filesRes.status);
        VfsEntry[] entries;
        foreach (f; filesRes.value) {
            entries ~= new VfsEntry(vfs, f);
        }
        return success!(VfsEntry[])(entries);
    }
    
    Outcome!IStream open(VfsOpenMode mode = VfsOpenMode.read) {
        return vfs.openStream(originalPath, mode);
    }

    override string toString() const {
        return format("VfsEntry(%s)", originalPath);
    }
}
