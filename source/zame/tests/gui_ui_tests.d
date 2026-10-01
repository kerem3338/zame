module zame.tests.gui_ui_tests;

import zame.core.gui.ui;

unittest {
    auto ui = new UISystem(1920, 1080, 16);

    auto p = 10.px;
    assert(p.toPx(ui) == 10.0f);
    assert(p.toIntPx(ui) == 10);

    auto r = 2.rem;
    assert(r.toPx(ui) == 32.0f);

    auto v = 50.vw;
    assert(v.toPx(ui) == 960.0f);

    auto vhLen = 25.vh;
    assert(vhLen.toPx(ui) == 270.0f);

    auto pc = 50.pct;
    assert(pc.toPx(ui, 400.0f) == 200.0f);
}

unittest {
    auto ui = new UISystem(1920, 1080, 16);

    auto m1 = min(10.px, 25.rem);
    assert(m1.toPx(ui) == 10.0f);

    auto m2 = min(500.px, 25.rem);
    assert(m2.toPx(ui) == 400.0f);

    auto mx = max(100.px, 10.rem);
    assert(mx.toPx(ui) == 160.0f);

    auto cl = clamp(50.px, 10.vw, 200.px);
    assert(cl.toPx(ui) == 192.0f);

    auto cl2 = clamp(50.px, 2.vw, 200.px);
    assert(cl2.toPx(ui) == 50.0f);
}

unittest {
    auto ui = new UISystem(1920, 1080, 16);

    auto expr = 50.pct - 20.px;
    assert(expr.toPx(ui, 1000.0f) == 480.0f);

    auto expr2 = 2.rem + 8.px;
    assert(expr2.toPx(ui) == 40.0f);

    auto expr3 = 1.rem * 2.5f;
    assert(expr3.toPx(ui) == 40.0f);
}

unittest {
    auto ui = new UISystem(1920, 1080, 16);

    // rem()/vw() at module level return Length; ui.rem()/ui.vw() return int (compat)
    auto m1 = ui.min(ui.percent(10), rem(25));
    assert(ui.resolve(m1, 500.0f) == 50.0f);
    assert(ui.resolveInt(m1, 500.0f) == 50);

    auto m2 = ui.min(ui.px(10), rem(25));
    assert(ui.resolve(m2) == 10.0f);

    auto mx = ui.max(ui.px(100), ui.percent(50));
    assert(ui.resolve(mx, 400.0f) == 200.0f);

    auto cl = ui.clamp(ui.px(10), vw(5), ui.px(50));
    assert(ui.resolve(cl) == 50.0f);

    auto calcExpr = ui.pct(100) - ui.px(20);
    assert(ui.resolve(calcExpr, 500.0f) == 480.0f);
}
