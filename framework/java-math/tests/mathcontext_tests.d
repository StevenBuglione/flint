module mathcontext_tests;

import flint.java.lang : IllegalArgumentException;
import flint.java.math.mathcontext : MathContext;
import flint.java.math.roundingmode : RoundingMode;

@safe:

static assert(!__traits(compiles, new MathContext(0, null)));

@("MathContext presets retain their settings and identity") unittest
{
    const MathContext decimal128 = MathContext.DECIMAL128;
    assert(decimal128 is MathContext.DECIMAL128);
    assert(decimal128.getPrecision() == 34 && decimal128.getRoundingMode() == RoundingMode.HALF_EVEN);
    assert(MathContext.DECIMAL64.toString() == "precision=16 roundingMode=HALF_EVEN");
    assert(MathContext.DECIMAL32.toString() == "precision=7 roundingMode=HALF_EVEN");
    assert(MathContext.UNLIMITED.toString() == "precision=0 roundingMode=HALF_UP");
}

@("MathContext equality and D keys use the two settings") unittest
{
    auto settings = new MathContext(6, RoundingMode.HALF_DOWN);
    auto parsed = new MathContext("precision=6 roundingMode=HALF_DOWN");
    assert(settings !is parsed && settings == parsed);
    assert(settings.hashCode() == parsed.hashCode());
    assert(!settings.equals(new MathContext(6)));
    assert(!settings.equals(new MathContext(7, RoundingMode.HALF_DOWN)));
    assert(!settings.equals(null));
    assert(!settings.equals(new Object()));
    assert(new MathContext(6).getRoundingMode() == RoundingMode.HALF_UP);

    const MathContext constSettings = settings;
    const MathContext constParsed = parsed;
    assert(constSettings == constParsed);

    int[MathContext] counts;
    counts[settings] = 9;
    assert(counts[parsed] == 9);
}

@("MathContext text accepts Java's signed precision and UTF-16 digits") unittest
{
    assert(new MathContext("precision=+００٧ roundingMode=UP").toString() == "precision=7 roundingMode=UP");
    assert(new MathContext("precision=-٠ roundingMode=DOWN").getPrecision() == 0);
    assert(new MathContext("precision=2147483647 roundingMode=UNNECESSARY").getPrecision() == int.max);
}

@("MathContext rejects out-of-range precision and malformed text") unittest
{
    import std.exception : assertThrown;

    assertThrown!IllegalArgumentException(new MathContext(-1));
    assertThrown!IllegalArgumentException(new MathContext(null));
    string missing;
    assertThrown!IllegalArgumentException(new MathContext(missing));
    foreach (text; [
        "", "precision= roundingMode=UP", "precision=+ roundingMode=UP",
        "precision=-1 roundingMode=UP", "precision=2147483648 roundingMode=UP",
        "precision=𝟟 roundingMode=UP", "precision=7  roundingMode=UP",
        "precision=7\troundingMode=UP", "precision=7 roundingMode=UP ", "precision=7 roundingMode=up",
    ])
        assertThrown!IllegalArgumentException(new MathContext(text));
}
