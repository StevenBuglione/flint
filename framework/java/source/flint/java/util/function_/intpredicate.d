/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.intpredicate;

@safe:

/// Java's `IntPredicate` contract (R9).
interface IntPredicate
{
    /// Whether `value` matches.
    bool test(int value);

    /// Call the predicate through a D delegate.
    final bool delegate(int) @safe asDelegate()
    {
        return &test;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static IntPredicate of()(bool delegate(int) @safe callback)
    {
        return new DelegatePredicate!()(callback);
    }
}

private final class DelegatePredicate() : IntPredicate
{
    private bool delegate(int) @safe callback;

    this(bool delegate(int) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override bool test(int value)
    {
        return callback(value);
    }
}
