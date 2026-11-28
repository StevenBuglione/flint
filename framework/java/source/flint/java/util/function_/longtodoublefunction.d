/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.longtodoublefunction;

@safe:

/// Java's `LongToDoubleFunction` contract (R9).
interface LongToDoubleFunction
{
    /// Apply the function to a long, returning a double.
    double applyAsDouble(long value);

    /// Call the function through a D delegate.
    final double delegate(long) @safe asDelegate()
    {
        return &applyAsDouble;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static LongToDoubleFunction of()(double delegate(long) @safe callback)
    {
        return new DelegateFunction!()(callback);
    }
}

private final class DelegateFunction() : LongToDoubleFunction
{
    private double delegate(long) @safe callback;

    this(double delegate(long) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override double applyAsDouble(long value)
    {
        return callback(value);
    }
}
