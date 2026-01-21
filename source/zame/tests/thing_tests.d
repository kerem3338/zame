module zame.tests.thing_tests;

import zame.core.thing;
import zame.core.common;

class TestThing : Thing {
    this() {
        super(Rect(0, 0, 10, 10));
    }
}

unittest {
    // Test Thing creation
    auto thing = new TestThing();
    assert(thing.rect.w == 10);
    assert(thing.rect.h == 10);
    assert(!thing.destroyed);
}

unittest {
    // Test Thing destruction
    auto thing = new TestThing();
    thing.destroy();
    assert(thing.destroyed);
}

unittest {
    // Test ThingManager
    auto manager = new ThingManager();
    auto thing1 = new TestThing();
    auto thing2 = new TestThing();
    
    manager.addThing(thing1);
    manager.addThing(thing2);
    
    assert(manager.getThingCount() == 2);
    assert(thing1.id > 0);
    assert(thing2.id > 0);
    assert(thing1.id != thing2.id);
}

unittest {
    // Test ThingManager ID generation
    auto manager = new ThingManager();
    auto thing = new TestThing();
    
    manager.addThing(thing);
    uint firstId = thing.id;
    
    manager.removeThing(firstId);
    
    auto thing2 = new TestThing();
    manager.addThing(thing2);
    
    // ID should be reused
    assert(manager.getThingCount() == 1);
}

unittest {
    // Test Thing tags
    auto thing = new TestThing();
    thing.addTag("player");
    thing.addTag("friendly");
    
    assert(thing.hasTag("player"));
    assert(thing.hasTag("friendly"));
    assert(!thing.hasTag("enemy"));
}

unittest {
    // Test Thing properties
    import std.variant;
    
    auto thing = new TestThing();
    thing.setProperty("health", Variant(100));
    thing.setProperty("name", Variant("TestEntity"));
    
    assert(thing.getProperty("health").get!int == 100);
    assert(thing.getProperty("name").get!string == "TestEntity");
}
