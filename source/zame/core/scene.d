module zame.core.scene;

import std.range;
import zame.core.common;
import zame.core.graphics;
import zame.core.platform;

abstract class Scene {
	SceneManager sceneManager;
	
	@property Instance instance() { return sceneManager ? sceneManager.instance : null; }

	abstract void start();
	
	abstract void stop();
	
	abstract void update(float deltaTime);
	
	/// Render with IGraphics (preferred for hardware acceleration and abstraction)
	void render(IGraphics g) {
		if (auto sw = cast(SoftwareGraphics)g) {
			render(sw.target);
		}
	}
	
	/// Legacy render hook with Surface (for backwards compatibility)
	void render(Surface surface) {}
	
	abstract void onEvent(Event event);

	void updateAudio() {}

	void onPause() {}
	void onResume() {}

	override string toString() const {
		return "Scene()";
	}
}

class SceneManager {
private:
	Scene[] scenes;
	Scene nextScene;

	enum PendingAction {
		none,
		change,
		push,
		pop
	}

	PendingAction pendingAction = PendingAction.none;

	Instance _instance;

public:
	@property Instance instance() {
		return _instance;
	}

	this(Instance instance) {
		_instance = instance;
	}

	/// Clears every scene and switches to a new one.
	void changeScene(Scene newScene) {
		nextScene = newScene;
		pendingAction = PendingAction.change;
	}

	/// Pushes a scene on top of the current one.
	void pushScene(Scene newScene) {
		nextScene = newScene;
		pendingAction = PendingAction.push;
	}

	/// Removes the current scene.
	void popScene() {
		pendingAction = PendingAction.pop;
	}

private:
	void processPendingAction() {
		final switch (pendingAction) {
			case PendingAction.none:
				return;

			case PendingAction.change:
				while (!scenes.empty) {
					scenes.back.stop();
					scenes.popBack();
				}

				if (nextScene !is null) {
					nextScene.sceneManager = this;
					nextScene.start();
					scenes ~= nextScene;
				}
				break;

			case PendingAction.push:
				if (!scenes.empty) {
					scenes.back.onPause();
				}

				if (nextScene !is null) {
					nextScene.sceneManager = this;
					nextScene.start();
					scenes ~= nextScene;
				}
				break;

			case PendingAction.pop:
				if (!scenes.empty) {
					auto scene = scenes.back;
					scene.stop();
					scenes.popBack();
				}

				if (!scenes.empty) {
					scenes.back.onResume();
				}
				break;
		}

		nextScene = null;
		pendingAction = PendingAction.none;
	}

public:
	void update(float deltaTime) {
		if (pendingAction != PendingAction.none) {
			processPendingAction();
		}

		if (!scenes.empty) {
			scenes.back.update(deltaTime);
		}
	}

	void updateAudio() {
		if (!scenes.empty) {
			scenes.back.updateAudio();
		}
	}

	void render(IGraphics g) {
		if (!scenes.empty) {
			scenes.back.render(g);
		}
	}

	void render(Surface surface) {
		if (!scenes.empty) {
			scenes.back.render(surface);
		}
	}

	void handleEvent(Event event) {
		if (!scenes.empty) {
			scenes.back.onEvent(event);
		}
	}

	Scene getCurrentScene() {
		if (scenes.empty) {
			return null;
		}

		return scenes.back;
	}

	size_t getSceneCount() {
		return scenes.length;
	}

	bool canPopScene() {
		return scenes.length > 1;
	}

	bool hasScene() {
		return !scenes.empty;
	}

	override string toString() const {
		return "SceneManager(currentScene: " ~ (scenes.empty ? "null" : scenes.back.toString()) ~ ")";
	}
}