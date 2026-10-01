module zame.core.fx.particle;

import std.math;
import std.random;
import std.algorithm : clamp, min, max;
import zame.core.common;
import zame.core.graphics;

struct Particle {
    Vec2 position;
    Vec2 velocity;
    Vec2 acceleration;

    Color startColor;
    Color endColor;

    float startSize = 4.0f;
    float endSize = 0.0f;

    float rotation = 0.0f;
    float angularVelocity = 0.0f;

    float life = 0.0f;
    float maxLife = 0.0f;

    @property bool isAlive() const pure nothrow @nogc {
        return life > 0.0f;
    }

    @property float progress() const pure nothrow @nogc {
        if (maxLife <= 0.0f) return 1.0f;
        return clamp(1.0f - (life / maxLife), 0.0f, 1.0f);
    }

    @property Color currentColor() const pure nothrow @nogc {
        float t = progress();
        float invT = 1.0f - t;

        ubyte r = cast(ubyte)(startColor.r * invT + endColor.r * t);
        ubyte g = cast(ubyte)(startColor.g * invT + endColor.g * t);
        ubyte b = cast(ubyte)(startColor.b * invT + endColor.b * t);
        ubyte a = cast(ubyte)(startColor.a * invT + endColor.a * t);

        return Color(r, g, b, a);
    }

    @property float currentSize() const pure nothrow @nogc {
        float t = progress();
        return startSize * (1.0f - t) + endSize * t;
    }
}

struct EmitterConfig {
    float spawnRate = 50.0f;
    size_t maxParticles = 300;
    bool loop = true;
    float duration = -1.0f;

    Vec2 positionVariance = Vec2(0, 0);

    Vec2 gravity = Vec2(0, 0);
    Vec2 baseAcceleration = Vec2(0, 0);
    float minSpeed = 30.0f;
    float maxSpeed = 100.0f;
    float minAngle = 0.0f;
    float maxAngle = 2.0f * cast(float)PI;

    float minLife = 0.4f;
    float maxLife = 1.2f;

    Color startColor = Color(255, 200, 50, 255);
    Color endColor = Color(255, 50, 0, 0);
    float startSize = 6.0f;
    float endSize = 1.0f;

    float minRotation = 0.0f;
    float maxRotation = 0.0f;
    float minAngularVelocity = 0.0f;
    float maxAngularVelocity = 0.0f;

    static EmitterConfig explosion(Color startColor = Color(255, 220, 80, 255), Color endColor = Color(200, 30, 0, 0)) {
        EmitterConfig cfg;
        cfg.loop = false;
        cfg.duration = 0.1f;
        cfg.maxParticles = 150;
        cfg.minSpeed = 80.0f;
        cfg.maxSpeed = 220.0f;
        cfg.minAngle = 0.0f;
        cfg.maxAngle = 2.0f * cast(float)PI;
        cfg.minLife = 0.3f;
        cfg.maxLife = 0.8f;
        cfg.startColor = startColor;
        cfg.endColor = endColor;
        cfg.startSize = 8.0f;
        cfg.endSize = 1.0f;
        cfg.gravity = Vec2(0, 50.0f);
        return cfg;
    }

    static EmitterConfig fire(Color startColor = Color(255, 230, 60, 255), Color endColor = Color(220, 20, 0, 0)) {
        EmitterConfig cfg;
        cfg.spawnRate = 80.0f;
        cfg.maxParticles = 200;
        cfg.loop = true;
        cfg.minSpeed = 30.0f;
        cfg.maxSpeed = 90.0f;
        cfg.minAngle = -cast(float)PI * 0.7f;
        cfg.maxAngle = -cast(float)PI * 0.3f;
        cfg.minLife = 0.4f;
        cfg.maxLife = 0.9f;
        cfg.startColor = startColor;
        cfg.endColor = endColor;
        cfg.startSize = 10.0f;
        cfg.endSize = 2.0f;
        cfg.positionVariance = Vec2(6.0f, 2.0f);
        cfg.gravity = Vec2(0, -40.0f);
        return cfg;
    }

    static EmitterConfig smoke(Color startColor = Color(140, 140, 150, 180), Color endColor = Color(80, 80, 90, 0)) {
        EmitterConfig cfg;
        cfg.spawnRate = 35.0f;
        cfg.maxParticles = 120;
        cfg.loop = true;
        cfg.minSpeed = 15.0f;
        cfg.maxSpeed = 45.0f;
        cfg.minAngle = -cast(float)PI * 0.65f;
        cfg.maxAngle = -cast(float)PI * 0.35f;
        cfg.minLife = 1.0f;
        cfg.maxLife = 2.0f;
        cfg.startColor = startColor;
        cfg.endColor = endColor;
        cfg.startSize = 5.0f;
        cfg.endSize = 18.0f;
        cfg.positionVariance = Vec2(4.0f, 2.0f);
        cfg.gravity = Vec2(0, -15.0f);
        return cfg;
    }

    static EmitterConfig sparks(Color color = Color(255, 255, 120, 255)) {
        EmitterConfig cfg;
        cfg.loop = false;
        cfg.duration = 0.05f;
        cfg.maxParticles = 60;
        cfg.minSpeed = 100.0f;
        cfg.maxSpeed = 300.0f;
        cfg.minAngle = 0.0f;
        cfg.maxAngle = 2.0f * cast(float)PI;
        cfg.minLife = 0.15f;
        cfg.maxLife = 0.45f;
        cfg.startColor = color;
        cfg.endColor = Color(color.r, color.g, color.b, 0);
        cfg.startSize = 3.0f;
        cfg.endSize = 0.5f;
        cfg.gravity = Vec2(0, 200.0f);
        return cfg;
    }

    static EmitterConfig fountain(Color color = Color(60, 160, 255, 220)) {
        EmitterConfig cfg;
        cfg.spawnRate = 90.0f;
        cfg.maxParticles = 250;
        cfg.loop = true;
        cfg.minSpeed = 120.0f;
        cfg.maxSpeed = 200.0f;
        cfg.minAngle = -cast(float)PI * 0.65f;
        cfg.maxAngle = -cast(float)PI * 0.35f;
        cfg.minLife = 0.8f;
        cfg.maxLife = 1.4f;
        cfg.startColor = color;
        cfg.endColor = Color(color.r, color.g, color.b, 0);
        cfg.startSize = 5.0f;
        cfg.endSize = 2.0f;
        cfg.positionVariance = Vec2(2.0f, 0.0f);
        cfg.gravity = Vec2(0, 180.0f);
        return cfg;
    }

    static EmitterConfig trail(Color color = Color(180, 210, 255, 160)) {
        EmitterConfig cfg;
        cfg.spawnRate = 40.0f;
        cfg.maxParticles = 80;
        cfg.loop = true;
        cfg.minSpeed = 0.0f;
        cfg.maxSpeed = 10.0f;
        cfg.minLife = 0.25f;
        cfg.maxLife = 0.5f;
        cfg.startColor = color;
        cfg.endColor = Color(color.r, color.g, color.b, 0);
        cfg.startSize = 6.0f;
        cfg.endSize = 0.5f;
        return cfg;
    }
}

class ParticleEmitter {
    Vec2 position;
    EmitterConfig config;

    private Particle[] pool;
    private float spawnAccumulator = 0.0f;
    private float activeTime = 0.0f;
    private bool _isEmitting = true;
    private Random rng;

    this(Vec2 position, EmitterConfig config) {
        this.position = position;
        this.config = config;
        this.rng = Random(unpredictableSeed);
        this.pool = new Particle[config.maxParticles];
    }

    @property bool isEmitting() const pure nothrow @nogc {
        return _isEmitting;
    }

    @property void isEmitting(bool value) pure nothrow @nogc {
        _isEmitting = value;
    }

    @property size_t activeParticleCount() const pure nothrow @nogc {
        size_t count = 0;
        foreach (ref p; pool) {
            if (p.isAlive) count++;
        }
        return count;
    }

    @property bool isFinished() const pure nothrow @nogc {
        if (_isEmitting && (config.loop || config.duration < 0 || activeTime < config.duration)) {
            return false;
        }
        return activeParticleCount == 0;
    }

    void start() {
        _isEmitting = true;
    }

    void stop() {
        _isEmitting = false;
    }

    void reset() {
        spawnAccumulator = 0.0f;
        activeTime = 0.0f;
        _isEmitting = true;
        foreach (ref p; pool) {
            p.life = 0.0f;
        }
    }

    void burst(int count) {
        foreach (_; 0 .. count) {
            spawnSingleParticle();
        }
    }

    private float randomRange(float minVal, float maxVal) {
        if (minVal >= maxVal) return minVal;
        return uniform(minVal, maxVal, rng);
    }

    private void spawnSingleParticle() {
        size_t freeIndex = pool.length;
        foreach (i, ref p; pool) {
            if (!p.isAlive) {
                freeIndex = i;
                break;
            }
        }
        if (freeIndex == pool.length) return;

        float angle = randomRange(config.minAngle, config.maxAngle);
        float speed = randomRange(config.minSpeed, config.maxSpeed);
        float life = randomRange(config.minLife, config.maxLife);

        float vx = cos(angle) * speed;
        float vy = sin(angle) * speed;

        float posX = position.x + randomRange(-config.positionVariance.x, config.positionVariance.x);
        float posY = position.y + randomRange(-config.positionVariance.y, config.positionVariance.y);

        pool[freeIndex].position = Vec2(posX, posY);
        pool[freeIndex].velocity = Vec2(vx, vy);
        pool[freeIndex].acceleration = config.baseAcceleration;
        pool[freeIndex].startColor = config.startColor;
        pool[freeIndex].endColor = config.endColor;
        pool[freeIndex].startSize = config.startSize;
        pool[freeIndex].endSize = config.endSize;
        pool[freeIndex].rotation = randomRange(config.minRotation, config.maxRotation);
        pool[freeIndex].angularVelocity = randomRange(config.minAngularVelocity, config.maxAngularVelocity);
        pool[freeIndex].life = life;
        pool[freeIndex].maxLife = life;
    }

    void update(float dt) {
        if (dt <= 0.0f) return;

        if (_isEmitting) {
            activeTime += dt;
            if (!config.loop && config.duration >= 0.0f && activeTime >= config.duration) {
                _isEmitting = false;
            } else if (config.spawnRate > 0.0f) {
                spawnAccumulator += dt;
                float interval = 1.0f / config.spawnRate;
                while (spawnAccumulator >= interval) {
                    spawnSingleParticle();
                    spawnAccumulator -= interval;
                }
            }
        }

        foreach (ref p; pool) {
            if (!p.isAlive) continue;

            p.life -= dt;
            if (p.life <= 0.0f) {
                p.life = 0.0f;
                continue;
            }

            p.velocity.x += (config.gravity.x + p.acceleration.x) * dt;
            p.velocity.y += (config.gravity.y + p.acceleration.y) * dt;

            p.position.x += p.velocity.x * dt;
            p.position.y += p.velocity.y * dt;

            p.rotation += p.angularVelocity * dt;
        }
    }

    void render(IGraphics g) {
        if (g is null) return;

        foreach (ref p; pool) {
            if (!p.isAlive) continue;

            float size = p.currentSize();
            if (size <= 0.0f) continue;

            Color c = p.currentColor();
            if (c.a == 0) continue;

            int px = cast(int)p.position.x;
            int py = cast(int)p.position.y;
            int halfSize = cast(int)(size / 2.0f);

            if (size <= 2.0f) {
                g.drawPoint(Point(px, py), c);
            } else if (size <= 4.0f) {
                g.drawRect(Rect(px - halfSize, py - halfSize, cast(int)size, cast(int)size), c);
            } else {
                g.drawFilledCircle(Point(px, py), halfSize, c);
            }
        }
    }

    void render(Surface surface) {
        if (surface is null) return;

        foreach (ref p; pool) {
            if (!p.isAlive) continue;

            float size = p.currentSize();
            if (size <= 0.0f) continue;

            Color c = p.currentColor();
            if (c.a == 0) continue;

            int px = cast(int)p.position.x;
            int py = cast(int)p.position.y;
            int halfSize = cast(int)(size / 2.0f);

            if (size <= 2.0f) {
                if (surface.isValidPoint(Point(px, py))) {
                    surface.setPixel(Point(px, py), c);
                }
            } else if (size <= 4.0f) {
                Graphics.drawRect(surface, c, Rect(px - halfSize, py - halfSize, cast(int)size, cast(int)size));
            } else {
                Graphics.drawFilledCircle(surface, c, Point(px, py), halfSize);
            }
        }
    }
}

class ParticleSystem {
    private ParticleEmitter[] emitters;

    ParticleEmitter addEmitter(Vec2 position, EmitterConfig config) {
        auto emitter = new ParticleEmitter(position, config);
        emitters ~= emitter;
        return emitter;
    }

    ParticleEmitter triggerBurst(Vec2 position, EmitterConfig config, int count) {
        auto emitter = addEmitter(position, config);
        emitter.burst(count);
        emitter.isEmitting = false;
        return emitter;
    }

    void removeEmitter(ParticleEmitter emitter) {
        foreach (i, e; emitters) {
            if (e is emitter) {
                emitters = emitters[0 .. i] ~ emitters[i + 1 .. $];
                return;
            }
        }
    }

    void clear() {
        emitters.length = 0;
    }

    @property size_t emitterCount() const pure nothrow @nogc {
        return emitters.length;
    }

    @property size_t totalActiveParticles() const pure nothrow @nogc {
        size_t count = 0;
        foreach (e; emitters) {
            count += e.activeParticleCount;
        }
        return count;
    }

    void update(float dt) {
        for (size_t i = 0; i < emitters.length;) {
            emitters[i].update(dt);

            if (emitters[i].isFinished) {
                emitters = emitters[0 .. i] ~ emitters[i + 1 .. $];
            } else {
                i++;
            }
        }
    }

    void render(IGraphics g) {
        foreach (e; emitters) {
            e.render(g);
        }
    }

    void render(Surface surface) {
        foreach (e; emitters) {
            e.render(surface);
        }
    }
}
