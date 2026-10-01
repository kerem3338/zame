module zame.core.fs.filesystem;

import std.path : isAbsolute, globMatch;
import std.datetime.systime : SysTime;

import zame.core.common;
import zame.core.fs.uri;
import zame.core.fs.path;
import zame.core.fs.mount;
import zame.core.fs.provider;
import zame.core.fs.entry;
import zame.core.fs.providers.file;
import zame.core.fs.providers.memory;
import zame.core.fs.providers.zip;
import zame.core.fs.stream;

class VirtualFileSystem {
    private MountManager _mounts;
    private FileProvider defaultFileProvider;

    this() {
        _mounts = new MountManager();
        defaultFileProvider = new FileProvider("");
    }

    @property MountManager mounts() {
        return _mounts;
    }

    void mount(string scheme, IFsProvider provider) {
        _mounts.mount(scheme, provider);
    }

    void mount(string scheme, string physicalPath) {
        _mounts.mount(scheme, new FileProvider(physicalPath));
    }

    void mountZip(string scheme, string zipPath) {
        _mounts.mount(scheme, new ZipProvider(zipPath));
    }

    MemoryProvider mountMemory(string scheme) {
        auto mem = new MemoryProvider();
        _mounts.mount(scheme, mem);
        return mem;
    }

    void unmount(string scheme, IFsProvider provider = null) {
        if (provider is null) {
            _mounts.clear(scheme);
        } else {
            _mounts.unmount(scheme, provider);
        }
    }

    bool isMounted(string scheme) const {
        return _mounts.isMounted(scheme);
    }

    string[] mountedSchemes() const {
        return _mounts.getSchemes();
    }

    FsPath resolve(string pathStr) {
        FsUri uri = FsUri.parse(pathStr);
        string normPath = normalizeVfsPath(uri.path);
        
        if (uri.scheme.length > 0) {
            auto providers = _mounts.getProviders(uri.scheme);
            for (ptrdiff_t i = providers.length - 1; i >= 0; i--) {
                auto p = providers[i];
                FsPath tryPath = FsPath(uri, normPath, p, "");
                if (p.exists(tryPath)) {
                    return tryPath;
                }
            }
            
            if (providers.length > 0) {
                return FsPath(uri, normPath, providers[$ - 1], "");
            }
            
            return FsPath(uri, normPath, defaultFileProvider, "");
        }
        
        return FsPath(FsUri("file", normPath), normPath, defaultFileProvider, "");
    }

    VfsEntry entry(string pathStr) {
        return new VfsEntry(this, pathStr);
    }

    VfsEntry opIndex(string pathStr) {
        return entry(pathStr);
    }
    
    Outcome!IStream openStream(string pathStr, VfsOpenMode mode = VfsOpenMode.read) {
        FsPath fspath = resolve(pathStr);
        if (fspath.provider) {
            return fspath.provider.open(fspath, mode);
        }
        return failure!IStream(Result.unknown_error, "No provider found for path");
    }

    Outcome!size_t readFile(string pathStr, ubyte[] buffer) {
        auto streamRes = openStream(pathStr, VfsOpenMode.read | VfsOpenMode.binary);
        if (!streamRes.ok) return failure!size_t(streamRes.status);
        auto stream = streamRes.value;
        auto res = stream.read(buffer);
        stream.close();
        return res;
    }
    
    Outcome!(ubyte[]) readAllBytes(string pathStr) {
        auto streamRes = openStream(pathStr, VfsOpenMode.read | VfsOpenMode.binary);
        if (!streamRes.ok) return failure!(ubyte[])(streamRes.status);
        auto stream = streamRes.value;
        ulong len = stream.length();
        ubyte[] buffer = new ubyte[cast(size_t)len];
        auto readRes = stream.read(buffer);
        stream.close();
        
        if (readRes.ok) {
            return success!(ubyte[])(buffer[0 .. readRes.value]);
        }
        return failure!(ubyte[])(readRes.status);
    }

    Outcome!string readText(string pathStr) {
        auto bytesRes = readAllBytes(pathStr);
        if (bytesRes.ok) {
            return success!string(cast(string)bytesRes.value);
        }
        return failure!string(bytesRes.status);
    }

    ResultStatus writeAllBytes(string pathStr, const(ubyte)[] data) {
        auto streamRes = openStream(pathStr, VfsOpenMode.write | VfsOpenMode.binary);
        if (!streamRes.ok) return streamRes.status;
        auto stream = streamRes.value;
        auto writeRes = stream.write(data);
        stream.close();
        
        if (writeRes.ok) {
            return ResultStatus(Result.ok);
        }
        return writeRes.status;
    }

    ResultStatus writeText(string pathStr, string content) {
        return writeAllBytes(pathStr, cast(const(ubyte)[])content);
    }

    ResultStatus appendBytes(string pathStr, const(ubyte)[] data) {
        auto streamRes = openStream(pathStr, VfsOpenMode.append | VfsOpenMode.write | VfsOpenMode.binary);
        if (!streamRes.ok) return streamRes.status;
        auto stream = streamRes.value;
        auto writeRes = stream.write(data);
        stream.close();
        
        if (writeRes.ok) {
            return ResultStatus(Result.ok);
        }
        return writeRes.status;
    }

    ResultStatus appendText(string pathStr, string content) {
        return appendBytes(pathStr, cast(const(ubyte)[])content);
    }

    ResultStatus copy(string srcStr, string dstStr) {
        auto readRes = readAllBytes(srcStr);
        if (!readRes.ok) return readRes.status;
        return writeAllBytes(dstStr, readRes.value);
    }

    ResultStatus move(string srcStr, string dstStr) {
        auto copyRes = copy(srcStr, dstStr);
        if (!copyRes.ok) return copyRes;
        auto rmRes = remove(srcStr);
        if (!rmRes.ok) return rmRes;
        return ResultStatus(Result.ok);
    }

    bool exists(string pathStr) {
        return resolve(pathStr).exists;
    }

    bool isDirectory(string pathStr) {
        return resolve(pathStr).isDirectory;
    }

    bool isFile(string pathStr) {
        return resolve(pathStr).isFile;
    }

    Outcome!ulong size(string pathStr) {
        return resolve(pathStr).size();
    }

    Outcome!SysTime modifiedTime(string pathStr) {
        return resolve(pathStr).modifiedTime();
    }

    ResultStatus mkdir(string pathStr, bool recursive = true) {
        FsPath fspath = resolve(pathStr);
        if (fspath.provider) {
            return fspath.provider.mkdir(fspath, recursive);
        }
        return ResultStatus(Result.unknown_error, "No provider found for path");
    }

    ResultStatus remove(string pathStr) {
        FsPath fspath = resolve(pathStr);
        if (fspath.provider) {
            return fspath.provider.remove(fspath);
        }
        return ResultStatus(Result.unknown_error, "No provider found for path");
    }

    ResultStatus rename(string srcStr, string newName) {
        FsPath fspath = resolve(srcStr);
        if (fspath.provider) {
            return fspath.provider.rename(fspath, newName);
        }
        return ResultStatus(Result.unknown_error, "No provider found for path");
    }

    Outcome!(FsItem[]) listDirectory(string pathStr) {
        FsPath fspath = resolve(pathStr);
        if (fspath.provider) {
            return fspath.provider.listDirectory(fspath);
        }
        return failure!(FsItem[])(Result.unknown_error, "No provider found for path");
    }

    Outcome!(string[]) listFiles(string pathStr, bool recursive = false) {
        string[] result;
        auto res = collectPaths(pathStr, recursive, true, false, "*", result);
        if (!res.ok) return failure!(string[])(res);
        return success!(string[])(result);
    }

    Outcome!(string[]) listDirectories(string pathStr, bool recursive = false) {
        string[] result;
        auto res = collectPaths(pathStr, recursive, false, true, "*", result);
        if (!res.ok) return failure!(string[])(res);
        return success!(string[])(result);
    }

    Outcome!(string[]) findFiles(string pathStr, string pattern = "*", bool recursive = false) {
        string[] result;
        auto res = collectPaths(pathStr, recursive, true, false, pattern, result);
        if (!res.ok) return failure!(string[])(res);
        return success!(string[])(result);
    }

    private ResultStatus collectPaths(string currentPath, bool recursive, bool includeFiles, bool includeDirs, string pattern, ref string[] outList) {
        auto listRes = listDirectory(currentPath);
        if (!listRes.ok) return listRes.status;

        foreach (item; listRes.value) {
            string childPath = joinVfsPath(currentPath, item.name);
            if (item.type == FsItemType.directory) {
                if (includeDirs && (pattern == "*" || globMatch(item.name, pattern))) {
                    outList ~= childPath;
                }
                if (recursive) {
                    auto recRes = collectPaths(childPath, recursive, includeFiles, includeDirs, pattern, outList);
                    if (!recRes.ok) return recRes;
                }
            } else {
                if (includeFiles && (pattern == "*" || globMatch(item.name, pattern))) {
                    outList ~= childPath;
                }
            }
        }
        return ResultStatus(Result.ok);
    }
}