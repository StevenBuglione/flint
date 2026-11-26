module app;

import flint.java.util.enumeration : Enumeration;

@safe:

private final class Counts : Enumeration!int
{
    private int remaining;

    mixin Enumeration!int.Defaults;

    this(int count)
    {
        remaining = count;
    }

    bool hasMoreElements()
    {
        return remaining > 0;
    }

    int nextElement()
    {
        return remaining--;
    }
}

int main(string[] args)
{
    Enumeration!int values = new Counts(cast(int)(args.length & 127));
    auto iterator = values.asIterator();
    if (args.length > 2)
        iterator.remove();
    return iterator.hasNext() ? iterator.next() : 0;
}
