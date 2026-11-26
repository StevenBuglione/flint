// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.lang.javaobject : JavaObject;

@safe:

private final class Key
{
    mixin JavaObject;

    private int value;

    this(int value)
    {
        this.value = value;
    }

    bool equals(Object other)
    {
        auto key = cast(Key) other;
        return key !is null && value == key.value;
    }

    int hashCode() pure nothrow @nogc
    {
        return value;
    }

    int compareTo(Key other) pure nothrow @nogc
    {
        return value - other.value;
    }
}

pragma(inline, false) private bool matches(Key original, Object same, Object larger, int value)
{
    return original.opEquals(same) && !original.opEquals(larger)
        && original.toHash() == cast(uint) value && original.opCmp(larger) < 0;
}

int main(string[] args)
{
    const value = cast(int)(args.length & 127);
    return matches(new Key(value), new Key(value), new Key(value + 1), value) ? 0 : 1;
}
