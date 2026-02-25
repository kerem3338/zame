module zame.core.audio;

import zame.core.common;
import zame.core.cache;

interface ISound {
    /** Play the sound */
    void play();
    
    /** Stop the sound */
    void stop();
    
    /** 0.0 to 1.0 */
    void setVolume(float volume);
    
    /** Check if sound is playing */
    bool isPlaying();
    
    /** Update sound (Required for live audio) */
    void update();
}

interface IAudioDevice {
    void init();
    void cleanup();
    
    Outcome!ISound loadSound(string path);
    Outcome!ISound loadMusic(string path);
    void setMasterVolume(float volume);
}

class NullSound : ISound {
    override void play() {}
    override void stop() {}
    override void setVolume(float volume) {}
    override bool isPlaying() { return false; }
    override void update() {}
}

class NullAudioDevice : IAudioDevice {
    override void init() {}
    override void cleanup() {}
    override Outcome!ISound loadSound(string path) {
        return success!ISound(new NullSound());
    }
    override Outcome!ISound loadMusic(string path) {
        return success!ISound(new NullSound());
    }
    override void setMasterVolume(float volume) {}
}

class SoundCache : CacheManager {
    private IAudioDevice device;
    
    this(IAudioDevice device) {
        this.device = device;
    }
    
    Outcome!ISound get(string path) {
        if (!has(path)) {
            auto res = device.loadSound(path);
            if (res.ok) {
                set(path, res.value);
            } else {
                return res;
            }
        }
        return success!ISound(acquire!ISound(path));
    }
}

class SoundManager {
    private SoundCache cache;
    private IAudioDevice device;
    private float masterVolume = 1.0f;

    this(IAudioDevice device) {
        this.device = device;
        this.cache = new SoundCache(device);
    }

    void play(string path, float volume = 1.0f) {
        auto res = cache.get(path);
        if (res.ok) {
            res.value.setVolume(volume);
            res.value.play();
        }
    }

    void stop(string path) {
        auto res = cache.get(path);
        if (res.ok) {
            res.value.stop();
        }
    }

    void release(string path) {
        cache.release(path);
    }

    void setMasterVolume(float volume) {
        this.masterVolume = volume;
        device.setMasterVolume(volume);
    }

    float getMasterVolume() {
        return masterVolume;
    }
}
