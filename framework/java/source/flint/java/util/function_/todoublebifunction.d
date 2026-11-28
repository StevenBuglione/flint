/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.todoublebifunction;

@safe:

/// Java's `ToDoubleBiFunction` contract (R9).
interface ToDoubleBiFunction(T, U)
{
    /// Apply the function to two arguments, returning a double.
    double applyAsDouble(T t, U u);

    /// Call the function through a D delegate.
    final double delegate(T, U) @safe asDelegate()
    {
        return &applyAsDouble;
    }

    /// A `ToDoubleBiFunction` calling `dg`.
    static ToDoubleBiFunction!(T, U) of(double delegate(T, U) @safe dg)
    {
        return new DelegateFunction!(T, U)(dg);
    }
}

private final class DelegateFunction(T, U) : ToDoubleBiFunction!(T, U)
{
    private double delegate(T, U) @safe dg;

    this(double delegate(T, U) @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    override double applyAsDouble(T t, U u)
    {
        return dg(t, u);
    }
}
