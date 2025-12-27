module my_scene;

import zame;
import std.stdio;
import std.math;
import core.runtime;
import core.sys.windows.dll;

// DLL Boilerplate for D
mixin SimpleDllMain;

class ExternalScene : Scene {
    Surface textSurf;
    BitmapFont font;
    float time = 0;

    this() {
        // Assuming resources are relative to the running executable (the engine)
        // or we need absolute paths. For now, let's assume we run from project root.
        font = new BitmapFont("resources/fonts/t33.png", "resources/fonts/t33.font-info", 2);
        textSurf = font.getText("HELLO FROM DLL!", Color(255, 0, 0), 48);
    }

    override void start() {
        writeln("External Scene Loaded and Started!");
    }

    override void stop() {
        writeln("External Scene Stopped.");
    }

    override void update(float dt) {
        time += dt;
    }

    override void render(Surface surface) {
        surface.fill(Color(0, 50, 0)); // Dark green background
        
        int x = (surface.width - textSurf.width) / 2;
        int y = (surface.height - textSurf.height) / 2;
        
        // Simple bounce effect
        y += cast(int)(sin(time * 5.0) * 50);

        surface.blit(textSurf, x, y);
    }

    override void onEvent(Event event) {
        if (event.type == EventType.keyPressed && event.key.key == ' ') {
            writeln("Space pressed in DLL scene!");
        }
    }
}

// Exported factory function
export extern(C) Scene createScene() {
    return new ExternalScene();
}
