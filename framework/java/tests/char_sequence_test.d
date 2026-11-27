module char_sequence_test;

import flint.java.lang : CanonicalCharSequence = CharSequence;
import flint.java.lang.charsequence : CharSequence;
import std.utf : toUTF8;

@safe:
static assert(is(CanonicalCharSequence == CharSequence));

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

@("CharSequence defaults and subsequences use UTF-16 units")
unittest
{
    CharSequence whole = new UnitSequence("A\U0001F680\u00E9"w);
    assert(!whole.isEmpty());
    assert(whole.length() == 4);
    assert(whole.charAt(1) == 0xD83D);
    assert(whole.charAt(2) == 0xDE80);
    assert(whole.subSequence(1, 3).toString() == "\U0001F680");
    assert(whole.subSequence(1, 2).charAt(0) == 0xD83D);
    assert(whole.subSequence(2, 2).isEmpty());
}
