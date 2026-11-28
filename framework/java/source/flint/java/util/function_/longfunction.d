/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.longfunction;

@safe:

/// Java's `LongFunction` contract (R9).
interface LongFunction(R)
{
    /// Apply the function to a long.
    R apply(long value);

    /// Call the function through a D delegate.
    final R delegate(long) @safe asDelegate()
    {
        return &apply;
    }

    /// A `LongFunction` calling `dg`.
    static LongFunction!R of(R delegate(long) @safe dg)
    {
        return new DelegateFunction!(R)(dg);
    }
}

private final class DelegateFunction(R) : LongFunction!(R)
{
    private R delegate(long) @safe dg;

    this(R delegate(long) @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    override R apply(long value)
    {
        return dg(value);
    }
}
