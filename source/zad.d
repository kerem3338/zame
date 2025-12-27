module zad;

import std.stdio;
import std.exception;
import std.string;
import std.file;
import std.traits;
import std.array;
import zame;

void writeU32(ref File f, uint v)
{
    f.rawWrite((&v)[0 .. 1]);
}

uint readU32(ref File f)
{
    uint v;
    f.rawRead((&v)[0 .. 1]);
    return v;
}

void writeString(ref File f, string s)
{
    writeU32(f, cast(uint)s.length);
    f.rawWrite(cast(const(ubyte)[])s);
}

string readString(ref File f)
{
    uint len = readU32(f);
    auto buf = new char[len];
    f.rawRead(buf[]);
    return buf.idup;
}

void writeSurface(ref File f, Surface s)
{
    writeU32(f, s.width);
    writeU32(f, s.height);
    writeU32(f, cast(uint)s.rawData.length);
    f.rawWrite(cast(const(ubyte)[])s.rawData);
}

Surface readSurface(ref File f)
{
    uint w = readU32(f);
    uint h = readU32(f);
    uint count = readU32(f);

    auto s = new Surface(w, h);
    enforce(count == s.rawData.length, "Surface mismatch");

    f.rawRead(cast(ubyte[])s.rawData);
    return s;
}

void writeIntArray(ref File f, int[] arr)
{
    writeU32(f, cast(uint)arr.length);
    f.rawWrite(cast(const(ubyte)[])arr);
}

int[] readIntArray(ref File f)
{
    uint count = readU32(f);
    auto arr = new int[count];
    f.rawRead(cast(ubyte[])arr);
    return arr;
}

enum ZadType : uint
{
    Int = 1,
    String = 2,
    Surface = 3,
    IntArray = 4,
    Float = 5,
    FloatArray = 6,
    Double = 7,
    DoubleArray = 8,
    Byte = 9,
    ByteArray = 10,
    Long = 11,
    LongArray = 12,
    Short = 13,
    ShortArray = 14,
    Struct = 50
}

align(1) struct ZadHeader
{
    char[4] magic;
    uint versionNumber;
    uint entryCount;
}

struct ZadEntry
{
    string name;
    ZadType type;
    uint size;
    File* file;
    long dataPos;

    int asInt()
    {
        file.seek(dataPos, SEEK_SET);
        int v;
        file.rawRead((&v)[0 .. 1]);
        return v;
    }

    string asString()
    {
        file.seek(dataPos, SEEK_SET);
        return readString(*file);
    }

    Surface asSurface()
    {
        file.seek(dataPos, SEEK_SET);
        return readSurface(*file);
    }

    T asValue(T)()
    {
        file.seek(dataPos, SEEK_SET);
        static if (is(T == int)) {
            int v;
            file.rawRead((&v)[0 .. 1]);
            return v;
        } else static if (is(T == float)) {
            float v;
            file.rawRead((&v)[0 .. 1]);
            return v;
        } else static if (is(T == double)) {
            double v;
            file.rawRead((&v)[0 .. 1]);
            return v;
        } else static if (is(T == long)) {
            long v;
            file.rawRead((&v)[0 .. 1]);
            return v;
        } else static if (is(T == string)) {
            return readString(*file);
        } else static if (is(T == Surface)) {
            return readSurface(*file);
        } else static if (is(T == struct)) {
            static if (__traits(hasMember, T, "deserialize"))
            {
                return val.deserialize(*file);
            }
            else
            {
                T val;
                foreach (ref field; val.tupleof)
                {
                    alias FT = typeof(field);
                    static if (is(FT == int)) field = readU32(*file);
                    else static if (is(FT == float)) {
                        float v; file.rawRead((&v)[0 .. 1]); field = v;
                    }
                    else static if (is(FT == double)) {
                        double v; file.rawRead((&v)[0 .. 1]); field = v;
                    }
                    else static if (is(FT == long)) {
                        long v; file.rawRead((&v)[0 .. 1]); field = v;
                    }
                    else static if (is(FT == string)) field = readString(*file);
                    else static if (is(FT == Surface)) field = readSurface(*file);
                    else static if (is(FT : U[], U)) {
                        uint count = readU32(*file);
                        field = new U[count];
                        file.rawRead(cast(ubyte[])field);
                    }
                    else static if (is(FT == struct)) field = asValue!FT();
                    else static assert(0, "Unsupported struct field type: " ~ FT.stringof);
                }
                return val;
            }
        } else {
             static assert(0, "Unsupported type: " ~ T.stringof);
        }
    }

    T[] asArray(T)()
    {
        file.seek(dataPos, SEEK_SET);
        uint count = readU32(*file);
        auto arr = new T[count];
        file.rawRead(cast(ubyte[])arr);
        return arr;
    }

}

enum Mode { Read, Write }

class ZadFile
{
private:
    File file;
    Mode mode;
    uint totalEntries;
    uint entriesLeft;
    uint written;
    long headerPos;
    bool closed;
    long firstEntryPos;

public:
    this(string filename, Mode m)
    {
        mode = m;

        if (mode == Mode.Write)
        {
            file = File(filename, "wb");

            ZadHeader h;
            h.magic = ['Z','A','D',0];
            h.versionNumber = 1;
            h.entryCount = 0;

            headerPos = file.tell();
            file.rawWrite((&h)[0 .. 1]);
            firstEntryPos = file.tell();
        }
        else
        {
            file = File(filename, "rb");

            ZadHeader h;
            file.rawRead((&h)[0 .. 1]);

            enforce(h.magic[0..3] == "ZAD", "Invalid ZAD");
            totalEntries = h.entryCount;
            entriesLeft = h.entryCount;
            headerPos = 0; // Assuming it starts at 0
            firstEntryPos = file.tell();
        }
    }

    void close()
    {
        if (closed) return;
        closed = true;

        if (mode == Mode.Write)
        {
            auto end = file.tell();
            file.seek(headerPos, SEEK_SET);

            ZadHeader h;
            h.magic = ['Z','A','D',0];
            h.versionNumber = 1;
            h.entryCount = written;

            file.rawWrite((&h)[0 .. 1]);
            file.seek(end, SEEK_SET);
        }

        file.close();
    }

    ~this()
    {
        close();
    }

    void putInt(string name, int v)
    {
        writeString(file, name);
        writeU32(file, ZadType.Int);
        writeU32(file, int.sizeof);
        file.rawWrite((&v)[0 .. 1]);
        written++;
    }

    void putString(string name, string s)
    {
        writeString(file, name);
        writeU32(file, ZadType.String);

        auto pos = file.tell();
        writeU32(file, 0);

        auto start = file.tell();
        writeString(file, s);
        auto end = file.tell();

        file.seek(pos, SEEK_SET);
        writeU32(file, cast(uint)(end - start));
        file.seek(end, SEEK_SET);

        written++;
    }

    void putSurface(string name, Surface s)
    {
        writeString(file, name);
        writeU32(file, ZadType.Surface);

        auto pos = file.tell();
        writeU32(file, 0);

        auto start = file.tell();
        writeSurface(file, s);
        auto end = file.tell();

        file.seek(pos, SEEK_SET);
        writeU32(file, cast(uint)(end - start));
        file.seek(end, SEEK_SET);

        written++;
    }

    void putIntArray(string name, int[] arr)
    {
        writeString(file, name);
        writeU32(file, ZadType.IntArray);

        auto pos = file.tell();
        writeU32(file, 0);

        auto start = file.tell();
        writeIntArray(file, arr);
        auto end = file.tell();

        file.seek(pos, SEEK_SET);
        writeU32(file, cast(uint)(end - start));
        file.seek(end, SEEK_SET);

        written++;
    }

    void putFloat(string name, float v)
    {
        writeString(file, name);
        writeU32(file, ZadType.Float);
        writeU32(file, float.sizeof);
        file.rawWrite((&v)[0 .. 1]);
        written++;
    }

    void putFloatArray(string name, float[] arr)
    {
        writeString(file, name);
        writeU32(file, ZadType.FloatArray);

        auto pos = file.tell();
        writeU32(file, 0);

        auto start = file.tell();
        writeU32(file, cast(uint)arr.length);
        file.rawWrite(cast(const(ubyte)[])arr);
        auto end = file.tell();

        file.seek(pos, SEEK_SET);
        writeU32(file, cast(uint)(end - start));
        file.seek(end, SEEK_SET);

        written++;
    }

    void putDouble(string name, double v)
    {
        writeString(file, name);
        writeU32(file, ZadType.Double);
        writeU32(file, double.sizeof);
        file.rawWrite((&v)[0 .. 1]);
        written++;
    }

    void putDoubleArray(string name, double[] arr)
    {
        writeString(file, name);
        writeU32(file, ZadType.DoubleArray);

        auto pos = file.tell();
        writeU32(file, 0);

        auto start = file.tell();
        writeU32(file, cast(uint)arr.length);
        file.rawWrite(cast(const(ubyte)[])arr);
        auto end = file.tell();

        file.seek(pos, SEEK_SET);
        writeU32(file, cast(uint)(end - start));
        file.seek(end, SEEK_SET);

        written++;
    }

    void putLong(string name, long v)
    {
        writeString(file, name);
        writeU32(file, ZadType.Long);
        writeU32(file, long.sizeof);
        file.rawWrite((&v)[0 .. 1]);
        written++;
    }

    void putLongArray(string name, long[] arr)
    {
        writeString(file, name);
        writeU32(file, ZadType.LongArray);

        auto pos = file.tell();
        writeU32(file, 0);

        auto start = file.tell();
        writeU32(file, cast(uint)arr.length);
        file.rawWrite(cast(const(ubyte)[])arr);
        auto end = file.tell();

        file.seek(pos, SEEK_SET);
        writeU32(file, cast(uint)(end - start));
        file.seek(end, SEEK_SET);

        written++;
    }

    void putStructRaw(T)(T s) if (is(T == struct))
    {
        static if (__traits(hasMember, T, "serialize"))
        {
            s.serialize(file);
        }
        else
        {
            foreach (ref field; s.tupleof)
            {
                alias FT = typeof(field);
                static if (is(FT == int)) writeU32(file, field);
                else static if (is(FT == float)) file.rawWrite((&field)[0 .. 1]);
                else static if (is(FT == double)) file.rawWrite((&field)[0 .. 1]);
                else static if (is(FT == long)) file.rawWrite((&field)[0 .. 1]);
                else static if (is(FT == string)) writeString(file, field);
                else static if (is(FT == Surface)) writeSurface(file, field);
                else static if (is(FT : U[], U)) {
                    writeU32(file, cast(uint)field.length);
                    file.rawWrite(cast(const(ubyte)[])field);
                }
                else static if (is(FT == struct)) putStructRaw(field);
                else static assert(0, "Unsupported struct field type: " ~ FT.stringof);
            }
        }
    }

    void put(T)(string name, T val)
    {
        static if (is(T == int)) putInt(name, val);
        else static if (is(T == string)) putString(name, val);
        else static if (is(T == Surface)) putSurface(name, val);
        else static if (is(T == float)) putFloat(name, val);
        else static if (is(T == double)) putDouble(name, val);
        else static if (is(T == long)) putLong(name, val);
        else static if (is(T : U[], U))
        {
            // ... (keep current array logic or consolidate)
            writeString(file, name);
            ZadType type;
            static if (is(U == int)) type = ZadType.IntArray;
            else static if (is(U == float)) type = ZadType.FloatArray;
            else static if (is(U == double)) type = ZadType.DoubleArray;
            else static if (is(U == long)) type = ZadType.LongArray;
            else static if (is(U == ubyte)) type = ZadType.ByteArray;
            else static if (is(U == short)) type = ZadType.ShortArray;
            else static assert(0, "Unsupported array type: " ~ U.stringof);

            writeU32(file, type);

            auto pos = file.tell();
            writeU32(file, 0);

            auto start = file.tell();
            writeU32(file, cast(uint)val.length);
            file.rawWrite(cast(const(ubyte)[])val);
            auto end = file.tell();

            file.seek(pos, SEEK_SET);
            writeU32(file, cast(uint)(end - start));
            file.seek(end, SEEK_SET);

            written++;
        }
        else static if (is(T == struct))
        {
            writeString(file, name);
            writeU32(file, ZadType.Struct);

            auto pos = file.tell();
            writeU32(file, 0);

            auto start = file.tell();
            putStructRaw(val);
            auto end = file.tell();

            file.seek(pos, SEEK_SET);
            writeU32(file, cast(uint)(end - start));
            file.seek(end, SEEK_SET);

            written++;
        }
        else static assert(0, "Unsupported type: " ~ T.stringof);
    }

    bool hasNext()
    {
        return entriesLeft > 0;
    }

    ZadEntry next()
    {
        enforce(entriesLeft > 0, "No entries");
        entriesLeft--;

        ZadEntry e;
        e.file = &file;
        e.name = readString(file);
        e.type = cast(ZadType)readU32(file);
        e.size = readU32(file);
        e.dataPos = file.tell();

        file.seek(e.dataPos + e.size, SEEK_SET);
        return e;
    }

    ZadEntry getEntry(string name)
    {
        enforce(mode == Mode.Read, "Cannot get entry in write mode");
        
        long oldPos = file.tell();
        uint oldLeft = entriesLeft;
        
        scope(exit) {
            file.seek(oldPos, SEEK_SET);
            entriesLeft = oldLeft;
        }

        file.seek(firstEntryPos, SEEK_SET);
        entriesLeft = totalEntries;

        while (hasNext())
        {
            auto e = next();
            if (e.name == name) return e;
        }

        throw new Exception("Entry not found: " ~ name);
    }

    uint count() { return totalEntries; }
}

void testZad()
{
	import std.conv;
    string testFile = "test.zad";

    struct PlayerStats {
        string name;
        int hp;
        int maxHp;
        float x, y;
        int[] inventory;
    }

    {
        auto z = new ZadFile(testFile, Mode.Write);
        z.put("hp", 100);
        z.put("game", "Zoda Engine");
        for (int i = 0; i < 20; i++) {
        	z.put("_"~i.to!string, i.to!int);
        }

        auto s = new Surface(8, 8);
        s.fill(Color(255, 0, 0, 255));
        z.put("logo", s);

        z.put("enemies", [1, 5, 9, 42]);
        z.put("speed", 3.14f);
        z.put("positions", [1.0f, 2.0f, 3.5f]);
        z.put("score", 9999999999L);
        
        PlayerStats ps = { "Aragorn", 90, 100, 150.5f, 200.1f, [1, 2, 55] };
        z.put("player", ps);

        z.close();
    }

    {
        auto z = new ZadFile(testFile, Mode.Read);
        while (z.hasNext())
        {
            auto e = z.next();
            write(e.name, " (", e.type, ") -> ");

            final switch (e.type)
            {
                case ZadType.Int: writeln(e.asValue!int()); break;
                case ZadType.String: writeln("\"", e.asValue!string(), "\""); break;
                case ZadType.Surface:
                {
                    auto s = e.asSurface();
                    writeln("Surface ", s.width, "x", s.height);
                    break;
                }
                case ZadType.IntArray: writeln(e.asArray!int()); break;
                case ZadType.Float: writeln(e.asValue!float()); break;
                case ZadType.FloatArray: writeln(e.asArray!float()); break;
                case ZadType.Double: writeln(e.asValue!double()); break;
                case ZadType.DoubleArray: writeln(e.asArray!double()); break;
                case ZadType.Byte: break;
                case ZadType.ByteArray: writeln(e.asArray!ubyte()); break;
                case ZadType.Long: writeln(e.asValue!long()); break;
                case ZadType.LongArray: writeln(e.asArray!long()); break;
                case ZadType.Short: break;
                case ZadType.ShortArray: writeln(e.asArray!short()); break;
                case ZadType.Struct: writeln("Struct Blob"); break;
            }
        }

        writeln("\n--- Testing random access ---");
        auto score = z.getEntry("score").asValue!long();
        writeln("Score (Random Access): ", score);

        auto enemies = z.getEntry("enemies").asArray!int();
        writeln("Enemies (Random Access): ", enemies);

        auto ps = z.getEntry("player").asValue!PlayerStats();
        writefln("Player stats (Random Access): name=%s, hp=%d/%d, pos=(%.2f, %.2f), inv=%s", 
            ps.name, ps.hp, ps.maxHp, ps.x, ps.y, ps.inventory);

        z.close();
    }
}
