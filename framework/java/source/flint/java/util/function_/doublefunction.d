/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.doublefunction;

@safe:

/// Java's `DoubleFunction` contract (R9).
interface DoubleFunction(R)
{
    /// Apply the function to a double.
    R apply(double value);

    /// Call the function through a D delegate.
    final R delegate(double) @safe asDelegate()
    {
        return &apply;
    }

    /// A `DoubleFunction` calling `dg`.
    static DoubleFunction!R of(R delegate(double) @safe dg)
    {
        return new DelegateFunction!(R)(dg);
    }
}

private final class DelegateFunction(R) : DoubleFunction!(R)
{
    private R delegate(double) @safe dg;

    this(R delegate(double) @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    override R apply(double value)
    {
        return dg(value);
    }
}
