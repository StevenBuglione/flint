/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.doubletolongfunction;

@safe:

/// Java's `DoubleToLongFunction` contract (R9).
interface DoubleToLongFunction
{
    /// Apply the function to a double, returning a long.
    long applyAsLong(double value);

    /// Call the function through a D delegate.
    final long delegate(double) @safe asDelegate()
    {
        return &applyAsLong;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static DoubleToLongFunction of()(long delegate(double) @safe callback)
    {
        return new DelegateFunction!()(callback);
    }
}

private final class DelegateFunction() : DoubleToLongFunction
{
    private long delegate(double) @safe callback;

    this(long delegate(double) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override long applyAsLong(double value)
    {
        return callback(value);
    }
}
