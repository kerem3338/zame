module zame.tests.fx_tests;

import zame.core.common;
import zame.core.graphics;
import zame.core.fx;

unittest {
    Particle p;
    p.life = 0.5f;
    p.maxLife = 1.0f;
    p.startColor = Color(255, 0, 0, 255);
    p.endColor = Color(0, 0, 255, 0);
    p.startSize = 10.0f;
    p.endSize = 2.0f;

    assert(p.isAlive);
    assert(p.progress > 0.49f && p.progress < 0.51f);
    assert(p.currentSize > 5.9f && p.currentSize < 6.1f);

    Color c = p.currentColor();
    assert(c.r > 120 && c.r < 135);
    assert(c.b > 120 && c.b < 135);
}

unittest {
    auto cfg = EmitterConfig.explosion();
    auto emitter = new ParticleEmitter(Vec2(100, 100), cfg);

    assert(emitter.activeParticleCount == 0);

    emitter.burst(20);
    assert(emitter.activeParticleCount == 20);

    emitter.update(0.1f);
    assert(emitter.activeParticleCount == 20);

    emitter.update(1.0f);
    assert(emitter.activeParticleCount == 0);
    assert(emitter.isFinished);
}

unittest {
    auto sys = new ParticleSystem();
    assert(sys.emitterCount == 0);

    auto e1 = sys.addEmitter(Vec2(50, 50), EmitterConfig.fire());
    auto e2 = sys.triggerBurst(Vec2(200, 200), EmitterConfig.sparks(), 15);

    assert(sys.emitterCount == 2);
    assert(sys.totalActiveParticles == 15);

    auto surf = new Surface(300, 300);
    auto g = new SoftwareGraphics(surf);
    sys.render(g);

    sys.update(0.5f);
    assert(e2.isFinished);
    assert(sys.emitterCount == 1);
}
