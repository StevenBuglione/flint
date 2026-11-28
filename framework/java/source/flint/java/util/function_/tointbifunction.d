/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.tointbifunction;

@safe:

/// Java's `ToIntBiFunction` contract (R9).
interface ToIntBiFunction(T, U)
{
    /// Apply the function to two arguments, returning an int.
    int applyAsInt(T t, U u);

    /// Call the function through a D delegate.
    final int delegate(T, U) @safe asDelegate()
    {
        return &applyAsInt;
    }

    /// A `ToIntBiFunction` calling `dg`.
    static ToIntBiFunction!(T, U) of(int delegate(T, U) @safe dg)
    {
        return new DelegateFunction!(T, U)(dg);
    }
}

private final class DelegateFunction(T, U) : ToIntBiFunction!(T, U)
{
    private int delegate(T, U) @safe dg;

    this(int delegate(T, U) @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    override int applyAsInt(T t, U u)
    {
        return dg(t, u);
    }
}
