module zame.core.fs.handle;

import zame.core.fs.path;
import std.datetime.systime : SysTime;

struct AssetVersion {
    ulong id;
    SysTime modified;

    string toString() const {
        import std.format : format;
        return format("v%d (%s)", id, modified.toString());
    }
}

class VfsHandle {
    FsPath path;
    AssetVersion version_;

    this(FsPath path, AssetVersion ver) {
        this.path = path;
        this.version_ = ver;
    }

    override string toString() {
        import std.format : format;
        return format("VfsHandle(path: %s, version: %s)", path.toString(), version_.toString());
    }
}
