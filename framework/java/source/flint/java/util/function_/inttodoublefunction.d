/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.inttodoublefunction;

@safe:

/// Java's `IntToDoubleFunction` contract (R9).
interface IntToDoubleFunction
{
    /// Apply the function to an int, returning a double.
    double applyAsDouble(int value);

    /// Call the function through a D delegate.
    final double delegate(int) @safe asDelegate()
    {
        return &applyAsDouble;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static IntToDoubleFunction of()(double delegate(int) @safe callback)
    {
        return new DelegateFunction!()(callback);
    }
}

private final class DelegateFunction() : IntToDoubleFunction
{
    private double delegate(int) @safe callback;

    this(double delegate(int) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override double applyAsDouble(int value)
    {
        return callback(value);
    }
}
