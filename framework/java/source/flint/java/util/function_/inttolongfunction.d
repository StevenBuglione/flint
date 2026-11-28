/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.inttolongfunction;

@safe:

/// Java's `IntToLongFunction` contract (R9).
interface IntToLongFunction
{
    /// Apply the function to an int, returning a long.
    long applyAsLong(int value);

    /// Call the function through a D delegate.
    final long delegate(int) @safe asDelegate()
    {
        return &applyAsLong;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static IntToLongFunction of()(long delegate(int) @safe callback)
    {
        return new DelegateFunction!()(callback);
    }
}

private final class DelegateFunction() : IntToLongFunction
{
    private long delegate(int) @safe callback;

    this(long delegate(int) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override long applyAsLong(int value)
    {
        return callback(value);
    }
}
