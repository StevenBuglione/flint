module app;

import flint.java.lang.number : Number;

@safe:

private final class IntegralNumber : Number
{
    private int value;

    this(int value)
    {
        this.value = value;
    }

    override int intValue()
    {
        return value;
    }

    override long longValue()
    {
        return value;
    }

    override float floatValue()
    {
        return value;
    }

    override double doubleValue()
    {
        return value;
    }
}

int main(string[] args)
{
    const input = cast(int) args.length + 0x10100;
    Number value = new IntegralNumber(input);
    return value.byteValue() == cast(byte) input && value.shortValue() == cast(short) input ? 0 : 1;
}
