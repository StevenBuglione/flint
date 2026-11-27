module app;

import flint.java.util.primitiveiterator : PrimitiveIteratorOfInt;

@safe:

private final class Counts : PrimitiveIteratorOfInt
{
    private int remaining;

    mixin PrimitiveIteratorOfInt.Defaults;

    this(int count)
    {
        remaining = count;
    }

    bool hasNext()
    {
        return remaining > 0;
    }

    int nextInt()
    {
        return remaining--;
    }

    void remove()
    {
    }
}

int main(string[] args)
{
    PrimitiveIteratorOfInt values = new Counts(cast(int)(args.length & 127));
    int sum = values.next();
    values.forEachRemaining((int value) { sum += value; });
    return sum & 127;
}
