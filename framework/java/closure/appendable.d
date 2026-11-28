module appendable_probe;

import flint.java.lang.appendable : Appendable, CharSequence;

@safe:

private final class CountingSink : Appendable
{
    int count;

    override CountingSink append(CharSequence sequence)
    {
        count += sequence is null ? 4 : sequence.length();
        return this;
    }

    override CountingSink append(CharSequence sequence, int start, int end)
    {
        count += end - start;
        return this;
    }

    override CountingSink append(wchar unit)
    {
        ++count;
        return this;
    }
}

pragma(inline, false) private void appendUnits(Appendable sink, int amount)
{
    sink.append(null).append(null, 0, amount).append('X');
}

int main(string[] args)
{
    auto sink = new CountingSink;
    appendUnits(sink, args.length & 3);
    return sink.count;
}
