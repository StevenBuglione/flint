/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.todoublefunction;

@safe:

/// Java's `ToDoubleFunction` contract (R9).
interface ToDoubleFunction(T)
{
    /// Apply the function to `value`, returning a double.
    double applyAsDouble(T value);

    /// Call the function through a D delegate.
    final double delegate(T) @safe asDelegate()
    {
        return &applyAsDouble;
    }

    /// A `ToDoubleFunction` calling `dg`.
    static ToDoubleFunction!T of(double delegate(T) @safe dg)
    {
        return new DelegateFunction!(T)(dg);
    }
}

private final class DelegateFunction(T) : ToDoubleFunction!(T)
{
    private double delegate(T) @safe dg;

    this(double delegate(T) @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    override double applyAsDouble(T value)
    {
        return dg(value);
    }
}
