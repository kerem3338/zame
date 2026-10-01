module zame.core.fs.path;

import zame.core.fs.uri;
import zame.core.fs.provider;
import zame.core.common;
import std.array : replace, split, join;
import std.string : strip;
import std.path : baseName, dirName, extension, buildPath;
import std.datetime.systime : SysTime;

struct FsPath {
    FsUri uri;
    string relativePath;
    IFsProvider provider;
    string physicalRoot;

    private IFsProvider getProv() const {
        return cast(IFsProvider)provider;
    }

    @property bool exists() const {
        auto p = getProv();
        if (p) {
            return p.exists(cast(FsPath)this);
        }
        return false;
    }

    @property bool isDirectory() const {
        auto p = getProv();
        if (p) {
            return p.isDirectory(cast(FsPath)this);
        }
        return false;
    }

    @property bool isFile() const {
        return exists && !isDirectory;
    }

    Outcome!ulong size() const {
        auto p = getProv();
        if (p) {
            return p.size(cast(FsPath)this);
        }
        return failure!ulong(Result.unknown_error, "No provider associated with FsPath");
    }

    Outcome!SysTime modifiedTime() const {
        auto p = getProv();
        if (p) {
            return p.modifiedTime(cast(FsPath)this);
        }
        return failure!SysTime(Result.unknown_error, "No provider associated with FsPath");
    }

    @property string name() const {
        return baseName();
    }

    @property string baseName() const {
        if (relativePath.length == 0) {
            return uri.scheme.length > 0 ? uri.scheme : "";
        }
        return .baseName(relativePath);
    }

    @property string dirName() const {
        if (relativePath.length == 0) return "";
        string d = .dirName(relativePath);
        return (d == ".") ? "" : d;
    }

    @property string extension() const {
        if (relativePath.length == 0) return "";
        return .extension(relativePath);
    }

    /// Returns physical path if available, or null
    @property string physicalPath() const {
        auto p = getProv();
        if (p) {
            return p.getPhysicalPath(cast(FsPath)this);
        }
        return null;
    }

    FsPath join(string subpath) const {
        string newRel = joinVfsPath(relativePath, subpath);
        string newUriPath = uri.path.length > 0 ? joinVfsPath(uri.path, subpath) : newRel;
        FsUri newUri = FsUri(uri.scheme, newUriPath);
        return FsPath(newUri, newRel, getProv(), physicalRoot);
    }

    FsPath opBinary(string op : "/")(string subpath) const {
        return join(subpath);
    }

    FsPath opBinary(string op : "~")(string subpath) const {
        return join(subpath);
    }

    string toString() const {
        import std.format : format;
        if (provider) {
            return format("FsPath(uri: %s, provider: %s, relative: %s)", uri.toString(), provider.name, relativePath);
        }
        return uri.toString();
    }
}

/// Normalizes VFS path preventing directory traversal like "assets://../secret.txt"
string normalizeVfsPath(string path) {
    string normalized = path.replace("\\", "/");
    
    // Check if path starts with a Windows drive letter (e.g. "C:/")
    string drivePrefix = "";
    if (normalized.length >= 2 && normalized[1] == ':') {
        drivePrefix = normalized[0 .. 2];
        normalized = normalized[2 .. $];
    }

    string[] parts = normalized.split("/");
    string[] result;
    
    foreach(part; parts) {
        if (part == "" || part == ".") {
            continue;
        } else if (part == "..") {
            if (result.length > 0) {
                result.length--;
            }
        } else {
            result ~= part;
        }
    }
    
    string res = result.join("/");
    if (drivePrefix.length > 0) {
        return drivePrefix ~ (res.length > 0 ? "/" ~ res : "");
    }
    return res;
}

/// Joins two VFS path components, maintaining URI schemes if present
string joinVfsPath(string base, string subpath) {
    auto uri = FsUri.parse(base);
    string normSub = normalizeVfsPath(subpath);
    if (uri.scheme.length > 0) {
        string joinedRel = (uri.path.length == 0) ? normSub : normalizeVfsPath(uri.path ~ "/" ~ normSub);
        return uri.scheme ~ "://" ~ joinedRel;
    }
    if (base.length == 0 || base == ".") return normSub;
    return normalizeVfsPath(base ~ "/" ~ normSub);
}
