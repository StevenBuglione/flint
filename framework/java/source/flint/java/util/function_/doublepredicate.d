/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.doublepredicate;

@safe:

/// Java's `DoublePredicate` contract (R9).
interface DoublePredicate
{
    /// Whether `value` matches.
    bool test(double value);

    /// Call the predicate through a D delegate.
    final bool delegate(double) @safe asDelegate()
    {
        return &test;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static DoublePredicate of()(bool delegate(double) @safe callback)
    {
        return new DelegatePredicate!()(callback);
    }
}

private final class DelegatePredicate() : DoublePredicate
{
    private bool delegate(double) @safe callback;

    this(bool delegate(double) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override bool test(double value)
    {
        return callback(value);
    }
}
