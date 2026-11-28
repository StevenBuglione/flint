/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.doubletointfunction;

@safe:

/// Java's `DoubleToIntFunction` contract (R9).
interface DoubleToIntFunction
{
    /// Apply the function to a double, returning an int.
    int applyAsInt(double value);

    /// Call the function through a D delegate.
    final int delegate(double) @safe asDelegate()
    {
        return &applyAsInt;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static DoubleToIntFunction of()(int delegate(double) @safe callback)
    {
        return new DelegateFunction!()(callback);
    }
}

private final class DelegateFunction() : DoubleToIntFunction
{
    private int delegate(double) @safe callback;

    this(int delegate(double) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override int applyAsInt(double value)
    {
        return callback(value);
    }
}
