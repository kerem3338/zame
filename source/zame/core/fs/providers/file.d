module zame.core.fs.providers.file;

import zame.core.fs.provider;
import zame.core.fs.stream;
import zame.core.fs.path;
import zame.core.fs.entry : FsItem, FsItemType;
import zame.core.common;

import std.file;
import std.stdio : File, SEEK_SET, SEEK_CUR, SEEK_END;
import std.path : buildPath, absolutePath, isAbsolute, baseName, dirName;
import std.exception : collectException;
import std.datetime.systime : SysTime;

class FileStream : IStream {
    private File file;
    private bool open;

    this(string path, string mode) {
        file = File(path, mode);
        open = true;
    }
    
    ~this() {
        if (open) close();
    }

    override ulong length() {
        try {
            return file.size;
        } catch (Exception) {
            return 0;
        }
    }

    override ulong position() {
        try {
            return file.tell();
        } catch (Exception) {
            return 0;
        }
    }

    override bool seek(long offset, SeekOrigin origin = SeekOrigin.begin) {
        try {
            int stdOrigin;
            final switch(origin) {
                case SeekOrigin.begin: stdOrigin = SEEK_SET; break;
                case SeekOrigin.current: stdOrigin = SEEK_CUR; break;
                case SeekOrigin.end: stdOrigin = SEEK_END; break;
            }
            file.seek(offset, stdOrigin);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    override Outcome!size_t read(ubyte[] buffer) {
        try {
            auto chunk = file.rawRead(buffer);
            return success!size_t(chunk.length);
        } catch (Exception e) {
            return failure!size_t(Result.unknown_error, e.msg);
        }
    }

    override Outcome!size_t write(const(ubyte)[] buffer) {
        try {
            file.rawWrite(buffer);
            file.flush();
            return success!size_t(buffer.length);
        } catch (Exception e) {
            return failure!size_t(Result.unknown_error, e.msg);
        }
    }

    override void close() {
        if (open) {
            try {
                file.flush();
                file.close();
            } catch (Exception) {}
            open = false;
        }
    }

    override bool isOpen() {
        return open && file.isOpen;
    }
}

class FileProvider : IFsProvider {
    private string physicalRoot;

    this(string physicalRoot = "") {
        if (physicalRoot.length > 0) {
            this.physicalRoot = absolutePath(physicalRoot);
        } else {
            this.physicalRoot = "";
        }
    }

    override @property string name() const {
        return "FileProvider";
    }

    @property string rootPath() const {
        return physicalRoot;
    }
    
    override string getPhysicalPath(FsPath path) {
        string rel = path.relativePath;
        if (rel.length == 0 || rel == ".") {
            return physicalRoot.length > 0 ? physicalRoot : ".";
        }
        if (isAbsolute(rel)) {
            return rel;
        }
        if (physicalRoot.length > 0) {
            return buildPath(physicalRoot, rel);
        }
        return rel;
    }

    override Outcome!IStream open(FsPath path, VfsOpenMode mode = VfsOpenMode.read) {
        try {
            string phys = getPhysicalPath(path);
            bool forWriting = (mode & VfsOpenMode.write) != 0 || (mode & VfsOpenMode.append) != 0 || (mode & VfsOpenMode.readWrite) != 0;
            if (forWriting) {
                string parentDir = dirName(phys);
                if (parentDir.length > 0 && parentDir != "." && !std.file.exists(parentDir)) {
                    std.file.mkdirRecurse(parentDir);
                }
            }
            return success!IStream(new FileStream(phys, toStdMode(mode)));
        } catch (Exception e) {
            return failure!IStream(Result.unknown_error, e.msg);
        }
    }

    override Outcome!ulong size(FsPath path) {
        string phys = getPhysicalPath(path);
        try {
            if (std.file.isDir(phys)) {
                return success!ulong(0);
            }
            return success!ulong(std.file.getSize(phys));
        } catch (Exception e) {
            return failure!ulong(Result.unknown_error, e.msg);
        }
    }

    override bool exists(FsPath path) {
        try {
            return std.file.exists(getPhysicalPath(path));
        } catch (Exception) {
            return false;
        }
    }

    override bool isDirectory(FsPath path) {
        try {
            return std.file.isDir(getPhysicalPath(path));
        } catch (Exception) {
            return false;
        }
    }
    
    override Outcome!SysTime modifiedTime(FsPath path) {
        try {
            return success!SysTime(std.file.timeLastModified(getPhysicalPath(path)));
        } catch (Exception e) {
            return failure!SysTime(Result.unknown_error, e.msg);
        }
    }
    
    override Outcome!(FsItem[]) listDirectory(FsPath path) {
        FsItem[] result;
        try {
            string phys = getPhysicalPath(path);
            if (!std.file.exists(phys)) {
                return failure!(FsItem[])(Result.file_not_found, "Directory does not exist");
            }
            if (!std.file.isDir(phys)) {
                return failure!(FsItem[])(Result.unknown_error, "Path is not a directory");
            }
            foreach (DirEntry entry; std.file.dirEntries(phys, std.file.SpanMode.shallow)) {
                FsItem item;
                item.name = baseName(entry.name);
                item.exists = true;
                try { item.size = entry.isDir ? 0 : entry.size; } catch(Exception) { item.size = 0; }
                item.type = entry.isDir ? FsItemType.directory : FsItemType.file;
                try { item.modifiedTime = entry.timeLastModified; } catch(Exception) {}
                result ~= item;
            }
            return success!(FsItem[])(result);
        } catch (Exception e) {
            return failure!(FsItem[])(Result.unknown_error, e.msg);
        }
    }

    override ResultStatus mkdir(FsPath path, bool recursive = false) {
        try {
            string phys = getPhysicalPath(path);
            if (recursive) {
                std.file.mkdirRecurse(phys);
            } else {
                std.file.mkdir(phys);
            }
            return ResultStatus(Result.ok);
        } catch (Exception e) {
            return ResultStatus(Result.unknown_error, e.msg);
        }
    }

    override ResultStatus remove(FsPath path) {
        try {
            string phys = getPhysicalPath(path);
            if (!std.file.exists(phys)) {
                return ResultStatus(Result.file_not_found, "Path does not exist");
            }
            if (std.file.isDir(phys)) {
                std.file.rmdirRecurse(phys);
            } else {
                std.file.remove(phys);
            }
            return ResultStatus(Result.ok);
        } catch (Exception e) {
            return ResultStatus(Result.unknown_error, e.msg);
        }
    }

    override ResultStatus rename(FsPath src, string newName) {
        try {
            string phys = getPhysicalPath(src);
            string dir = dirName(phys);
            string newPhys = buildPath(dir, newName);
            std.file.rename(phys, newPhys);
            return ResultStatus(Result.ok);
        } catch (Exception e) {
            return ResultStatus(Result.unknown_error, e.msg);
        }
    }
}
