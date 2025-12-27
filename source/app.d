import zame;
import std;
import platforms.pwin32;
import platforms.praylib;
import core.thread: Thread;
import std.format;
import std.datetime;
import std.datetime.stopwatch;
import std.math: sin, cos;
import core.sys.windows.windows;

import zad : testZad;

auto PI = 3.14159;

SceneManager g_sceneManager;

extern(C) alias CreateSceneFunc = Scene function();

void loadAndSwitchToScene(string dllPath) {
	writeln("Attempting to load DLL: ", dllPath);
	
	auto lib = LoadLibraryA(dllPath.toStringz);
	
	if (lib is null) {
		writeln("Failed to load library: ", dllPath);
		return;
	}
	
	auto proc = GetProcAddress(lib, "createScene");
	if (proc is null) {
		writeln("Could not find 'createScene' symbol in DLL. Error: ", GetLastError());
		FreeLibrary(lib);
		return;
	}
	
	CreateSceneFunc createScene = cast(CreateSceneFunc)proc;
	
	try {
		Scene newScene = createScene();
		writeln("Successfully created scene from DLL");

		g_sceneManager.changeScene(newScene);
	} catch (Throwable e) {
		writeln("Error creating scene: ", e.msg);
		FreeLibrary(lib);
	}
}

class MainMenuScene : Scene {
	Surface titleText;
	string[] options = ["Play", "About", "Exit"];
	size_t selectedOption = 0;
	BitmapFont font;
	BitmapFont smallFont;
	
	this() {
		font = new BitmapFont("resources/fonts/t33.png", "resources/fonts/t33.font-info", 2);
		smallFont = new BitmapFont("resources/fonts/t33.png", "resources/fonts/t33.font-info", 1);
		
		titleText = font.getText("MAIN MENU", Color(50, 100, 200), 48);
		
	}
	
	override void start() {
		writeln("MainMenuScene started");
	}
	
	override void stop() {
		writeln("MainMenuScene stopped");
	}
	
	override void update(float dt) {
	}
	
	override void render(Surface surface)
	{
		surface.fill(Color(30, 30, 50));

		int titleY = surface.height / 6;
		blitCentered(titleText, surface, -1, titleY);

		Surface[] optionSurfaces;
		optionSurfaces.length = options.length;

		foreach (i, option; options)
		{
			string text = (i == selectedOption) ? "> " ~ option : option;
			optionSurfaces[i] = smallFont.getText(text, Color(0, 0, 0), 32);
		}

		int y = titleY + titleText.height + 40;

		foreach (opSurface; optionSurfaces)
		{
			blitCentered(opSurface, surface, -1, y);
			y += opSurface.height + 12;
		}
	}

	
	override void onEvent(Event event)
	{
		if (event.type != EventType.keyPressed)
			return;

		switch (event.key.code)
		{
			case KeyCode.Escape:
				writeln("ESC pressed - exiting...");
				break;

			case KeyCode.ArrowUp:
				if (selectedOption == 0)
					selectedOption = options.length - 1;
				else
					selectedOption--;
				break;

			case KeyCode.ArrowDown:
				selectedOption = (selectedOption + 1) % options.length;
				break;

			case KeyCode.Space:
				writeln("Space pressed - selected: ", options[selectedOption]);
				g_sceneManager.changeScene(new GameScene());
				break;

			case KeyCode.L:
				loadAndSwitchToScene("examples/external_scene/external_scene.dll");
				break;

			default:
				break;
		}
	}

}

class GameScene : Scene {
	BitmapFont font;
	BitmapFont smallFont;
	ResourceManager rmg;
	int x, y;
	uint score;

	void updateScoreText() {
		rmg.data["score_text"] = font.getText(format("Score: %d", score), Color(255,0,0), 32);
	}

	this() {
		font = new BitmapFont("resources/fonts/t33.png", "resources/fonts/t33.font-info", 2);
		smallFont = new BitmapFont("resources/fonts/t33.png", "resources/fonts/t33.font-info", 1);
		
		rmg = new ResourceManager();
		rmg.data["score"] = 0;
		this.updateScoreText();

	}
	
	override void start() {
		writeln("GameScene started");
	}
	
	override void stop() {
		writeln("GameScene stopped");
	}
	
	override void update(float dt) {
		score++;
		updateScoreText();
	}
	
	override void render(Surface surface) {
		surface.fill(Color(50, 30, 30));
		
		int tileSize = 32;
		for (int y = 0; y < surface.height; y += tileSize) {
			for (int x = 0; x < surface.width; x += tileSize) {
				bool isWhite = ((x / tileSize) + (y / tileSize)) % 2 == 0;
				

				Color color = isWhite ? Colors.white : Colors.black;

				Graphics.drawRect(surface, color, Rect(Point(x, y), Size(tileSize, tileSize)));
			}
		}

		Graphics.drawLine(surface, Colors.blue, Point(0, 0), Point(instance.window.width, instance.window.height), 5);
		Graphics.drawLine(surface, Colors.blue, Point(0, instance.window.height), Point(instance.window.width, 0), 5);

		Graphics.drawRect(surface, Colors.red, Rect(Point(this.x-10, this.y-10), Size(20,20)));
		surface.blit(rmg.data["score_text"].get!Surface, Point(20,20));
	}
	
	override void onEvent(Event event) {
		if (event.type == EventType.mouseMoved) {
			x = event.mouseMoved.x;
			y = event.mouseMoved.y;
			
		}
		if (event.type == EventType.keyPressed) {
			switch (event.key.code) {
				case KeyCode.Escape:
					break;

				default: break;
			}
		}
	}
}

class MadeInZameScene : Scene {
	Surface zameLogo;
	Surface engineText;
	Surface[] aboutTextSurfaces;

	BitmapFont font;

	float rotation = 0;
	int alpha;
	float dt;

	this() {
		string[] aboutZameText = [
			"Zame Engine Is Developed By Kerem ATA",
			"Engine Is Powered By D Programming Language"
		];

		zameLogo = new Surface(0, 0);
		loadFromPng(zameLogo, "resources/images/zame.png");

		font = new BitmapFont(
			"resources/fonts/t33.png",
			"resources/fonts/t33.font-info",
			2
		);

		engineText = font.getText(
			"Made in Zame Engine",
			Color(0, 0, 0),
			42
		);

		aboutTextSurfaces.length = aboutZameText.length;
		for (int i = 0; i < aboutZameText.length; i++) {
			aboutTextSurfaces[i] = font.getText(
				aboutZameText[i],
				Color(0, 0, 0),
				24
			);
		}
	}

	override void start() {
		writeln("MadeInZameScene started");
	}

	override void stop() {
		writeln("MadeInZameScene stopped");
	}

	override void update(float dt) {
		this.dt=dt;
		rotation += dt * 90;
		if (rotation >= 360)
			rotation -= 360;

		if (alpha>=255) {
			g_sceneManager.changeScene(new MainMenuScene());
		}
	}

	override void render(Surface surface) {
		alpha+=(122*dt).to!int;

		surface.fill(Color(240, 240, 255));
		

		int logoX = surface.width / 2 - zameLogo.width / 2;
		int logoY = surface.height / 2 - zameLogo.height / 2;

		int offsetX = cast(int)(20 * sin(rotation * PI / 180.0));
		int offsetY = cast(int)(20 * cos(rotation * PI / 180.0));

		surface.blit(zameLogo, logoX + offsetX, logoY + offsetY);

		int titleX = (surface.width - engineText.width) / 2;
		surface.blit(engineText, titleX, 50);

		int startY = surface.height / 2 + zameLogo.height / 2 + 30;
		foreach (i, txt; aboutTextSurfaces) {
			int x = (surface.width - txt.width) / 2;
			surface.blit(txt, x, (startY + i * 30).to!int);
		}

		Graphics.drawRect(
			surface,
			Color(0, 0, 0, alpha),
			Rect(Point(0, 0), Size(surface.width, surface.height))
		);

	}


	override void onEvent(Event event) {
		if (event.type == EventType.keyPressed) {
			switch (event.key.code) {
				case KeyCode.Escape:
				case KeyCode.Space:
					g_sceneManager.changeScene(new MainMenuScene());
					break;

				default:
					break;
			}
		}
	}
}


int main() {
	import zad: testZad;
	//testZad();

	
	Window window = new Window(800, 600, "Zame Engine Demo");
	auto platform = new RaylibPlatform();
	
	Instance instance = new Instance(window, platform);
	
	window.platform = platform;
	platform.instanceRef = instance;
	
	if (platform.createWindow(window) != 0) {
		writeln("Failed to create window");
		return 1;
	}
	
	platform.setTargetFps(60);

	writeln(format("Zame Engine\nPlatform: %s", instance.platform.platformName));
	
	SceneManager sceneManager = new SceneManager(instance);
	g_sceneManager = sceneManager;
	
	sceneManager.changeScene(new MadeInZameScene());
	//sceneManager.changeScene(new MainMenuScene());
	
	StopWatch frameTimer;
	frameTimer.start();
	
	bool shouldExit = false;
	
	while (platform.isRunning() && !shouldExit) {
		float deltaTime = cast(float)frameTimer.peek().total!"msecs" / 1000.0f;
		frameTimer.reset();
		
		platform.processMessages();
		
		if (!platform.isRunning()) {
			break;
		}
		
		auto events = instance.pollEvents();
		foreach (event; events) {
			sceneManager.handleEvent(event);
			
			if (event.type == EventType.keyPressed && event.key.code == KeyCode.F4 && (event.key.mods & Modifiers.Alt)) {
				shouldExit = true;
			}
		}
		
		sceneManager.update(deltaTime);
		
		Surface surface = window.surface;
		sceneManager.render(surface);
		
		platform.invalidate();
		
	}
	
	platform.cleanup();
	writeln("Uygulama başarıyla sonlandı.");
	
	return 0;
}
