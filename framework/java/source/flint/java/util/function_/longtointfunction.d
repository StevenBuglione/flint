/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.longtointfunction;

@safe:

/// Java's `LongToIntFunction` contract (R9).
interface LongToIntFunction
{
    /// Apply the function to a long, returning an int.
    int applyAsInt(long value);

    /// Call the function through a D delegate.
    final int delegate(long) @safe asDelegate()
    {
        return &applyAsInt;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static LongToIntFunction of()(int delegate(long) @safe callback)
    {
        return new DelegateFunction!()(callback);
    }
}

private final class DelegateFunction() : LongToIntFunction
{
    private int delegate(long) @safe callback;

    this(int delegate(long) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override int applyAsInt(long value)
    {
        return callback(value);
    }
}
