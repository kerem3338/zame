module zame.core.thing;

import zame;
import std.variant;
import std.algorithm;
import std.array;
import std.stdio;
import std.format;

struct ThingEvent {
	string name;
	Variant data;
	Thing sender;
	Thing receiver;
}

class Thing {
	Rect rect;
	string[] tags;
	string type;
	Variant[string] properties;
	
	uint id;
	AnimationManager animMgr;
	ThingManager manager;
	bool destroyed = false;
	
	void delegate(ThingEvent) onEvent;
	
	this(Rect rect) {
		this.rect = rect;
	}
	
	void onCreated() {}
	void onDestroyed() {}
	void onUpdated(float dt) {}

	void update(float dt) {
		if (animMgr !is null) {
			animMgr.update(dt);
		}
		onUpdated(dt);
	}

	void destroy() {
		if (destroyed) return;
		onDestroyed();
		destroyed = true;
	}
	
	Surface getSurface() {
		return animMgr !is null ? animMgr.getCurrentFrame() : null;
	}
	
	void sendEventTo(Thing other, string eventName, Variant data = Variant()) {
		if (other is null || other.destroyed) return;
		
		ThingEvent event;
		event.name = eventName;
		event.data = data;
		event.sender = this;
		event.receiver = other;
		
		if (other.onEvent !is null) {
			other.onEvent(event);
		}
	}
	
	void broadcastEvent(ThingManager manager, string eventName, Variant data = Variant()) {
		foreach(thing; manager.getAllThings()) {
			if (thing != this && !thing.destroyed) {
				sendEventTo(thing, eventName, data);
			}
		}
	}

	bool hasTag(string tag) {
		foreach(t; tags) {
			if (t == tag) return true;
		}
		return false;
	}
	
	void addTag(string tag) {
		if (!hasTag(tag)) {
			tags ~= tag;
		}
	}
	
	void setProperty(string key, Variant value) {
		properties[key] = value;
	}
	
	Variant getProperty(string key, Variant defaultValue = Variant()) {
		return key in properties ? properties[key] : defaultValue;
	}

	string info() {
		return format("Entity (Id: %d, type: %s)\nRect: %s\nTags:%s\nPropertys:%s\nDestroyed: %s\n", id, type, rect, tags, properties, destroyed);
	}
	
	override string toString() const {
		return format("Thing(id: %d, type: %s)", id, type);
	}
}

class ThingManager {
	private Thing[] things;
	private uint nextId = 1;
	private uint[] freeIds;
	
	this() {}
	
	uint generateId() {
		if (freeIds.length > 0) {
			return freeIds[0..1][0];
			freeIds = freeIds[1..$];
		}
		return nextId++;
	}
	
	void freeId(uint id) {
		freeIds ~= id;
	}
	
	Thing getThingFromId(uint thingId) {
		foreach(thing; things) {
			if (thing.id == thingId) return thing;
		}
		return null;
	}
	
	void addThing(Thing thing) {
		if (thing.id == 0) {
			thing.id = generateId();
		}
		thing.manager = this;
		things ~= thing;
		thing.onCreated();
	}
	
	void removeThing(uint id) {
		auto thing = getThingFromId(id);
		if (thing !is null) {
			thing.destroy();
			freeId(id);
		}
		things = things.filter!(t => t.id != id).array;
	}
	
	void destroyThing(uint id) {
		auto thing = getThingFromId(id);
		if (thing !is null) {
			thing.destroy();
			freeId(id);
			things = things.filter!(t => t.id != id).array;
		}
	}
	
	void updateAll(float dt) {
		foreach(thing; things) {
			if (!thing.destroyed) {
				thing.update(dt);
			}
		}
		things = things.filter!(t => !t.destroyed).array;
	}
	
	Thing[] getAllThings() {
		return things.dup;
	}
	
	Thing[] getThingsWithTag(string tag) {
		return things.filter!(t => t.hasTag(tag)).array;
	}
	
	Thing[] getThingsOfType(string type) {
		return things.filter!(t => t.type == type).array;
	}
	
	void sendEvent(uint targetId, string eventName, Variant data = Variant(), Thing sender = null) {
		auto target = getThingFromId(targetId);
		if (target !is null) {
			if (sender is null) {
				target.sendEventTo(target, eventName, data);
			} else {
				sender.sendEventTo(target, eventName, data);
			}
		}
	}
	
	uint getThingCount() {
		return cast(uint)things.length;
	}
	
	uint getNextId() {
		return nextId;
	}
	
	void clear() {
		foreach(thing; things) {
			thing.destroy();
		}
		things.length = 0;
		freeIds.length = 0;
		nextId = 1;
	}
	
}