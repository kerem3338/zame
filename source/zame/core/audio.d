module zame.core.audio;

import zame.core.common;

interface ISound {
    void play();
    void stop();
    void setVolume(float volume); // 0.0 to 1.0
    bool isPlaying();
    void update(); // For streaming or maintenance
}

interface IAudioDevice {
    void init();
    void cleanup();
    
    Outcome!ISound loadSound(string path);
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
    override void setMasterVolume(float volume) {}
}
