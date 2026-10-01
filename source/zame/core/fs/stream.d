module zame.core.fs.stream;

import zame.core.common;

enum SeekOrigin {
    begin,
    current,
    end
}

enum VfsOpenMode : uint {
    read = 1 << 0,
    write = 1 << 1,
    append = 1 << 2,
    readWrite = 1 << 3,
    binary = 1 << 4
}

string toStdMode(VfsOpenMode mode) {
    bool r = (mode & VfsOpenMode.read) != 0;
    bool w = (mode & VfsOpenMode.write) != 0;
    bool a = (mode & VfsOpenMode.append) != 0;
    bool rw = (mode & VfsOpenMode.readWrite) != 0;
    bool b = (mode & VfsOpenMode.binary) != 0;

    string s = "";
    if (a) s = "a";
    else if (w) s = "w";
    else s = "r";

    if (rw) s ~= "+";
    if (b) s ~= "b";
    return s;
}

interface IStream {
    ulong length();
    ulong position();
    bool seek(long offset, SeekOrigin origin = SeekOrigin.begin);
    
    Outcome!size_t read(ubyte[] buffer);
    Outcome!size_t write(const(ubyte)[] buffer);
    
    void close();
    bool isOpen();
}
