module zame.core.scene;

import zame.core.common;
import zame.core.graphics;
import zame.core.platform;

abstract class Scene {
	SceneManager sceneManager;
	
	@property Instance instance() { return sceneManager ? sceneManager.instance : null; }

	abstract void start();
	
	abstract void stop();
	
	abstract void update(float deltaTime);
	
	abstract void render(Surface surface);
	
	abstract void onEvent(Event event);

	void updateAudio() {}

	override string toString() const {
		return "Scene()";
	}
}

class SceneManager {
private:
	Scene currentScene;
	Scene nextScene;
	bool shouldChangeScene = false;
	Instance _instance;
	
public:
	@property Instance instance() { return _instance; }

	this(Instance instance) {
		this._instance = instance;
		currentScene = null;
		nextScene = null;
	}
	
	void changeScene(Scene newScene) {
		nextScene = newScene;
		shouldChangeScene = true;
	}
	
	void update(float deltaTime) {
		if (shouldChangeScene && nextScene !is null) {
			if (currentScene !is null) {
				currentScene.stop();
			}
			
			currentScene = nextScene;
			currentScene.sceneManager = this;
			currentScene.start();
			
			nextScene = null;
			shouldChangeScene = false;
		}
		
		if (currentScene !is null) {
			currentScene.update(deltaTime);
		}
	}
	
	void updateAudio() {
		if (currentScene !is null) {
			currentScene.updateAudio();
		}
	}
	
	void render(Surface surface) {
		if (currentScene !is null) {
			currentScene.render(surface);
		}
	}
	
	void handleEvent(Event event) {
		if (currentScene !is null) {
			currentScene.onEvent(event);
		}
	}
	
	Scene getCurrentScene() {
		return currentScene;
	}
	
	bool hasScene() {
		return currentScene !is null;
	}

	override string toString() const {
		return "SceneManager(currentScene: "~ (currentScene !is null ? currentScene.toString() : "null") ~")";
	}
}
