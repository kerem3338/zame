module zame.core.cache;

import std.variant;

class KeyValueStore
{
protected:
    Variant[string] storage;

public:
    void set(T)(string key, T value)
    {
        storage[key] = Variant(value);
    }

    bool has(string key)
    {
        return (key in storage) !is null;
    }

    T get(T)(string key, T defaultValue = T.init)
    {
        auto ptr = key in storage;
        if (ptr is null)
            return defaultValue;

        return ptr.get!T;
    }

    void remove(string key)
    {
        storage.remove(key);
    }

    void clear()
    {
        storage = null;
    }
}

class ConfigManager : KeyValueStore
{
    void setString(string key, string value)
    {
        set(key, value);
    }

    string getString(string key, string def = "")
    {
        return get!string(key, def);
    }

    void setInt(string key, int value)
    {
        set(key, value);
    }

    int getInt(string key, int def = 0)
    {
        return get!int(key, def);
    }
}


class CacheManager : KeyValueStore
{
    private size_t[string] refCounts;

    T acquire(T)(string key)
    {
        if (!has(key))
            return T.init;

        refCounts[key]++;
        return get!T(key);
    }

    void release(string key)
    {
        if (key in refCounts)
        {
            if (refCounts[key] > 0)
                refCounts[key]--;

            if (refCounts[key] == 0)
            {
                remove(key);
                refCounts.remove(key);
            }
        }
    }
}
