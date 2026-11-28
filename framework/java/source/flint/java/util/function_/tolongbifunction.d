/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.tolongbifunction;

@safe:

/// Java's `ToLongBiFunction` contract (R9).
interface ToLongBiFunction(T, U)
{
    /// Apply the function to two arguments, returning a long.
    long applyAsLong(T t, U u);

    /// Call the function through a D delegate.
    final long delegate(T, U) @safe asDelegate()
    {
        return &applyAsLong;
    }

    /// A `ToLongBiFunction` calling `dg`.
    static ToLongBiFunction!(T, U) of(long delegate(T, U) @safe dg)
    {
        return new DelegateFunction!(T, U)(dg);
    }
}

private final class DelegateFunction(T, U) : ToLongBiFunction!(T, U)
{
    private long delegate(T, U) @safe dg;

    this(long delegate(T, U) @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    override long applyAsLong(T t, U u)
    {
        return dg(t, u);
    }
}
