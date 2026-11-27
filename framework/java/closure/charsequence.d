module charsequence_probe;

import flint.java.lang.charsequence : CharSequence;

@safe:

private final class AsciiSequence : CharSequence
{
    private string value;

    this(string value)
    {
        this.value = value;
    }

    override int length()
    {
        return cast(int) value.length;
    }

    override wchar charAt(int index)
    {
        return value[index];
    }

    override AsciiSequence subSequence(int start, int end)
    {
        return new AsciiSequence(value[start .. end]);
    }

    override string toString() const
    {
        return value;
    }

    mixin CharSequence.Defaults;
}

pragma(inline, false) private int firstUnit(CharSequence sequence)
{
    if (sequence.isEmpty())
        return 0;
    return sequence.subSequence(0, 1).charAt(0) & 127;
}

int main(string[] args)
{
    return firstUnit(new AsciiSequence(args.length > 1 ? "x" : ""));
}
