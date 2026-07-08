import zame;
import std.stdio;
import std.datetime.stopwatch;
import platforms.pwin32;
import std.path;
import std.file;

string exeDir;

class HelloWorldScene : Scene {
    BitmapFont font;
    Surface textSurface;

    this() {
        font = new BitmapFont("../../resources/fonts/t33.png", "../../resources/fonts/t33.font-info", 2);
        textSurface = font.getText("Hello, Zame Engine!", Color(255, 255, 255), 48);
    }

    override void start() {
        instance.logger.info("Hello World Scene started");
    }

    override void stop() {
        instance.logger.info("Hello World Scene stopped");
    }

    override void update(float dt) {

    }

    override void render(Surface surface) {
        surface.fill(Color(0, 0, 0));
        
        blitCentered(textSurface, surface, -1, -1);
    }

    override void onEvent(Event event) {
    }
}

void main() {
    auto window = new Window(800, 600, "Zame Hello World");
    auto platform = new Win32Platform();
    auto instance = new Instance(window, platform);

    window.platform = platform;
    platform.instanceRef = instance;

    if (platform.createWindow(window) != 0) {
        instance.logger.error("Failed to create window");
        return;
    }

    instance.doInitJobs();
    instance.logger.addHandler(new ConsoleHandler());

    auto sceneManager = new SceneManager(instance);
    sceneManager.changeScene(new HelloWorldScene());

    StopWatch frameTimer;
    frameTimer.start();

    while (platform.isRunning()) {
        float dt = cast(float)frameTimer.peek().total!"msecs" / 1000.0f;
        frameTimer.reset();

        platform.processMessages();
        
        if (!platform.isRunning()) break;

        auto events = instance.pollEvents();
        foreach (event; events) {
            sceneManager.handleEvent(event);
            if (event.type == EventType.keyPressed && event.key.code == KeyCode.Escape) {
                platform.cleanup();
                return;
            }
        }

        sceneManager.update(dt);
        sceneManager.render(window.surface);
        
        platform.invalidate();
    }

    platform.cleanup();
}
