module zame.core.cache;

import std.variant;
import std.typecons;
import std.conv;
import std.traits : Parameters;

class KeyValueEvent(D) {
    private D[] _delegates;

    void opOpAssign(string op)(D d) {
        static if (op == "+") {
            _delegates ~= d;
        } else static if (op == "-") {
            int idx = -1;
            foreach (i, del; _delegates) {
                if (del == d) { idx = i; break; }
            }
            if (idx >= 0) {
                _delegates = _delegates.remove(idx);
            }
        }
    }

    /// remove all delegates
    void clear() { _delegates = null; }

    /// true if no delegates are registered
    bool empty() const { return _delegates.length == 0; }

    /// number of registered delegates
    size_t length() const { return _delegates.length; }

    /// invoke with no arguments
    void fire()() if (is(D == void delegate())) {
        foreach (d; _delegates) {
            d();
        }
    }

    /// invoke with a reference argument
    void fire(Args)(ref Args args) if (is(D == void delegate(ref Args))) {
        foreach (d; _delegates) {
            d(args);
        }
    }
}

struct ConfigCreatedEvent {
    ConfigManager manager;
    string key;
    Variant value;
    ConfigValueFlags flags;
}

struct ConfigChangedEvent {
    ConfigManager manager;
    string key;
    Variant oldValue;
    Variant newValue;
    ConfigValueFlags flags;
}

struct ConfigRemovedEvent {
    ConfigManager manager;
    string key;
    Variant oldValue;
    ConfigValueFlags flags;
}

struct ConfigFlagsChangedEvent {
    ConfigManager manager;
    string key;
    ConfigValueFlags oldFlags;
    ConfigValueFlags newFlags;
}

enum ConfigValueFlags : uint {
    none            = 0,
    readOnly        = 1 << 0,
    typeMustBeSame  = 1 << 1,
    disableRemove   = 1 << 2,
}

struct ConfigValue {
    Variant value;
    ConfigValueFlags flags = ConfigValueFlags.none;

    @property ConfigValueFlags allFlags() const { return flags; }
    @property bool isReadOnly() const { return (flags & ConfigValueFlags.readOnly) != 0; }
    @property bool isTypeMustBeSame() const { return (flags & ConfigValueFlags.typeMustBeSame) != 0; }
    @property bool isDisableRemove() const { return (flags & ConfigValueFlags.disableRemove) != 0; }

    bool hasFlags(ConfigValueFlags mask) const { return (flags & mask) == mask; }

    T get(T)(T defaultValue = T.init) const {
        try { return value.get!T; }
        catch (VariantException) { return defaultValue; }
    }

    bool set(T)(T newValue) {
        if (isReadOnly) return false;

        static if (is(T == Variant)) {
            value = newValue;
            return true;
        } else {
            if (isTypeMustBeSame) {
                if (value.type != typeid(T))
                    return false;
            }
            value = Variant(newValue);
            return true;
        }
    }

    bool setFlags(ConfigValueFlags newFlags) {
        if (isReadOnly) return false;
        flags = newFlags;
        return true;
    }

    bool addFlags(ConfigValueFlags mask) {
        if (isReadOnly) return false;
        flags |= mask;
        return true;
    }

    bool removeFlags(ConfigValueFlags mask) {
        if (isReadOnly) return false;
        flags &= ~mask;
        return true;
    }
}

class KeyValueStore {
protected:
    Variant[string] storage;

public:
    void set(T)(string key, T value) { storage[key] = Variant(value); }
    bool has(string key) { return (key in storage) !is null; }
    T get(T)(string key, T defaultValue = T.init) {
        auto ptr = key in storage;
        if (ptr is null) return defaultValue;
        return ptr.get!T;
    }
    void remove(string key) { storage.remove(key); }
    void clear() { storage.clear(); }
}

class ConfigManager : KeyValueStore {
    private ConfigValue[string] configStore;

    public:
        KeyValueEvent!(void delegate(ref ConfigCreatedEvent)) onCreated;
        KeyValueEvent!(void delegate(ref ConfigChangedEvent)) onChanged;
        KeyValueEvent!(void delegate(ref ConfigRemovedEvent)) onRemoved;
        KeyValueEvent!(void delegate(ref ConfigFlagsChangedEvent)) onFlagsChanged;
        KeyValueEvent!(void delegate()) onCleared;

    this() {
        onCreated = new typeof(onCreated)();
        onChanged = new typeof(onChanged)();
        onRemoved = new typeof(onRemoved)();
        onFlagsChanged = new typeof(onFlagsChanged)();
        onCleared = new typeof(onCleared)();
    }

    void set(T)(string key, T value, ConfigValueFlags flags = ConfigValueFlags.none, bool force = false) {
        if (auto p = key in configStore) {
            if (!force && p.isReadOnly)
                throw new Exception("Config key '" ~ key ~ "' is read-only and cannot be changed.");

            if (p.isTypeMustBeSame) {
                static if (!is(T == Variant)) {
                    if (p.value.type != typeid(T))
                        throw new Exception(
                            "Config key '" ~ key ~ "' type mismatch. Expected '" ~
                            p.value.type.toString() ~
                            "', got '" ~
                            typeid(T).toString() ~ "'."
                        );
                }
            }

            Variant oldValue = p.value;
            ConfigValueFlags oldFlags = p.flags;

            bool valueChanged = (p.value != Variant(value));
            if (valueChanged) {
                p.value = Variant(value);
            }

            ConfigValueFlags newFlags = oldFlags;
            if (!force && flags != ConfigValueFlags.none) {
                newFlags = oldFlags | flags;
                if (newFlags != oldFlags) {
                    p.flags = newFlags;
                }
            }

            if (valueChanged) {
                ConfigChangedEvent ev;
                ev.manager = this;
                ev.key = key;
                ev.oldValue = oldValue;
                ev.newValue = p.value;
                ev.flags = p.flags;
                onChanged.fire(ev);
            }

            if (newFlags != oldFlags) {
                ConfigFlagsChangedEvent ev;
                ev.manager = this;
                ev.key = key;
                ev.oldFlags = oldFlags;
                ev.newFlags = newFlags;
                onFlagsChanged.fire(ev);
            }

            return;
        }

        configStore[key] = ConfigValue(Variant(value), flags);

        ConfigCreatedEvent ev;
        ev.manager = this;
        ev.key = key;
        ev.value = Variant(value);
        ev.flags = flags;
        onCreated.fire(ev);
    }

    T get(T)(string key, T defaultValue = T.init) {
        if (auto p = key in configStore) {
            try { return p.value.get!T; }
            catch (VariantException) { return defaultValue; }
        }
        return super.get!T(key, defaultValue);
    }

    string getString(string key, string def = "") { return get!string(key, def); }
    int    getInt   (string key, int    def = 0) { return get!int   (key, def); }
    bool   getBool  (string key, bool   def = false) { return get!bool  (key, def); }
    float  getFloat (string key, float  def = 0.0f) { return get!float (key, def); }

    override void remove(string key) {
        if (auto p = key in configStore) {
            if (p.isDisableRemove)
                throw new Exception("Config key '" ~ key ~ "' is protected and cannot be removed.");

            ConfigRemovedEvent ev;
            ev.manager = this;
            ev.key = key;
            ev.oldValue = p.value;
            ev.flags = p.flags;
            onRemoved.fire(ev);

            configStore.remove(key);
            return;
        }
        super.remove(key);
    }

    override bool has(string key) {
        if (key in configStore) return true;
        return super.has(key);
    }

    bool contains(string key) {
        return has(key);
    }

    override void clear() {
        foreach (key, ref cv; configStore) {
            if (!cv.isReadOnly && !cv.isDisableRemove)
                configStore.remove(key);
        }
        super.clear();
        onCleared.fire();
    }

    ConfigValueFlags getFlags(string key) {
        if (auto p = key in configStore) return p.flags;
        return ConfigValueFlags.none;
    }

    bool updateFlags(string key, ConfigValueFlags addFlags, ConfigValueFlags removeFlags = ConfigValueFlags.none) {
        if (auto p = key in configStore) {
            if (p.isReadOnly) return false;
            ConfigValueFlags oldFlags = p.flags;
            ConfigValueFlags newFlags = (p.flags | addFlags) & ~removeFlags;
            if (newFlags != oldFlags) {
                p.flags = newFlags;
                // Fire event
                ConfigFlagsChangedEvent ev;
                ev.manager = this;
                ev.key = key;
                ev.oldFlags = oldFlags;
                ev.newFlags = newFlags;
                onFlagsChanged.fire(ev);
            }
            return true;
        }
        return false;
    }

    bool isReadOnly(string key) {
        if (auto p = key in configStore) return p.isReadOnly;
        return false;
    }

    bool isRemoveDisabled(string key) {
        if (auto p = key in configStore) return p.isDisableRemove;
        return false;
    }

    string[] keys() {
        string[] result;
        foreach (key; configStore.keys) result ~= key;
        foreach (key; storage.keys) if (!(key in configStore)) result ~= key;
        return result;
    }

    string[] configKeys() { return configStore.keys; }
    string[] legacyKeys() { return storage.keys; }

    bool tryGet(T)(string key, out T value) {
        if (auto p = key in configStore) {
            try {
                value = p.value.get!T;
                return true;
            } catch (VariantException) {
                return false;
            }
        }
        return false;
    }
    T getOrCreate(T)(string key, T defaultValue, ConfigValueFlags flags = ConfigValueFlags.none) {
        if (auto p = key in configStore) {
            try { return p.value.get!T; }
            catch (VariantException) { /* fall through to create */ }
        }
        set(key, defaultValue, flags);
        return defaultValue;
    }
}

class CacheManager : KeyValueStore {
    private size_t[string] refCounts;

    T acquire(T)(string key) {
        if (!has(key)) return T.init;
        refCounts[key]++;
        return get!T(key);
    }

    void release(string key) {
        if (key in refCounts) {
            if (refCounts[key] > 0) refCounts[key]--;
            if (refCounts[key] == 0) {
                remove(key);
                refCounts.remove(key);
            }
        }
    }
}