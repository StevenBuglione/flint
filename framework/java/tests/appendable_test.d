module appendable_test;

import flint.java.lang : CanonicalAppendable = Appendable;
import flint.java.lang.appendable : Appendable;
import flint.java.lang.charsequence : CharSequence;
import std.utf : toUTF8, toUTF16;

@safe:
static assert(is(CanonicalAppendable == Appendable));

private final class UnitSequence : CharSequence
{
    private wstring units;

    this(wstring units)
    {
        this.units = units;
    }

    override int length()
    {
        return cast(int) units.length;
    }

    override wchar charAt(int index)
    {
        return units[index];
    }

    override UnitSequence subSequence(int start, int end)
    {
        return new UnitSequence(units[start .. end]);
    }

    override string toString() const
    {
        return toUTF8(units);
    }

    mixin CharSequence.Defaults;
}

private final class UnitSink : Appendable
{
    wchar[] units;

    override UnitSink append(CharSequence sequence)
    {
        units ~= sequence is null ? "null"w : toUTF16(sequence.toString());
        return this;
    }

    override UnitSink append(CharSequence sequence, int start, int end)
    {
        auto text = sequence is null ? "null"w : toUTF16(sequence.toString());
        units ~= text[start .. end];
        return this;
    }

    override UnitSink append(wchar unit)
    {
        units ~= unit;
        return this;
    }
}

@("Appendable appends text, UTF-16 ranges and units through the same sink")
unittest
{
    auto concrete = new UnitSink;
    Appendable sink = concrete;

    assert(sink.append(null) is sink);
    assert(concrete.units == "null"w);

    concrete.units.length = 0;
    assert(sink.append(new UnitSequence("A\U0001F680\u00E9"w)) is sink);
    assert(concrete.units == "A\U0001F680\u00E9"w);

    concrete.units.length = 0;
    assert(sink.append(new UnitSequence("A\U0001F680\u00E9"w), 1, 3) is sink);
    assert(concrete.units == "\U0001F680"w);

    concrete.units.length = 0;
    assert(sink.append(new UnitSequence("ab"w), 1, 1) is sink);
    assert(concrete.units.length == 0);

    assert(sink.append(cast(wchar) 0xD83D) is sink);
    assert(concrete.units == [cast(wchar) 0xD83D]);

    concrete.units.length = 0;
    assert(sink.append(null, 1, 3) is sink);
    assert(concrete.units == "ul"w);
}
