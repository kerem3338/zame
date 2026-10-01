module zame.core.fs.provider;

import zame.core.common;
import zame.core.fs.stream;
import zame.core.fs.path;
import zame.core.fs.entry : FsItem;
import std.datetime.systime : SysTime;

interface IFsProvider {
    /// Returns the provider name (e.g. "FileProvider")
    @property string name() const;
    
    /// Returns physical filesystem path if backed by real filesystem, otherwise null
    string getPhysicalPath(FsPath path);

    /// Open a stream for reading/writing
    Outcome!IStream open(FsPath path, VfsOpenMode mode = VfsOpenMode.read);
    
    /// Get size of the file
    Outcome!ulong size(FsPath path);
    
    /// Check if the path exists
    bool exists(FsPath path);
    
    /// Check if the path is a directory
    bool isDirectory(FsPath path);
    
    /// Get the last modified time of the file
    Outcome!SysTime modifiedTime(FsPath path);
    
    /// List contents of a directory
    Outcome!(FsItem[]) listDirectory(FsPath path);
    
    /// Create a directory
    ResultStatus mkdir(FsPath path, bool recursive = false);
    
    /// Remove a file or directory
    ResultStatus remove(FsPath path);
    
    /// Rename a file or directory
    ResultStatus rename(FsPath src, string newName);
}
