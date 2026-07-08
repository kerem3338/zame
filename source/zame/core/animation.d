module zame.core.animation;

import zame.core.common;
import zame.core.graphics;

class Animation {
	Surface[] frames;
	size_t currentFrame;
	Timer timer;

	this(Surface[] frames, Timer timer) {
		this.frames = frames;
		this.timer = timer;
	}

	void update(float dt) {
		if (timer.tick()) {
			currentFrame = (currentFrame + 1) % frames.length;
		}
	}

	void reset() {
		timer.reset();
		currentFrame = 0;
	}

	Surface getCurrentFrame() {
		return frames[currentFrame];
	}

	Surface getFrame(size_t index) {
		return frames[index];
	}
}

class AnimationManager {
	Animation[string] animations;
	Animation currentAnim;
	string currentAnimName;

	this(Animation[string] animations) {
		this.animations = animations;
	}

	Outcome!bool setCurrentAnimation(string id) {
		if (auto p = id in animations) {
			currentAnim = *p;
			currentAnimName = id;
			return success(true);
		}
		
		return failure!bool(Result.animation_not_exists, "Animation '" ~ id ~ "' does not exist");
	}

	void reset() {
		foreach(Animation animation; animations) {
			animation.reset();
		}
	}

	void update(float dt) {
		if (currentAnim is null) return;

		currentAnim.update(dt);
	}

	Surface getCurrentFrame() {
		if (currentAnim is null) return getErrorSurface(32,32);

		return currentAnim.getCurrentFrame();
	}
}