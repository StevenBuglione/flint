/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.longpredicate;

@safe:

/// Java's `LongPredicate` contract (R9).
interface LongPredicate
{
    /// Whether `value` matches.
    bool test(long value);

    /// Call the predicate through a D delegate.
    final bool delegate(long) @safe asDelegate()
    {
        return &test;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static LongPredicate of()(bool delegate(long) @safe callback)
    {
        return new DelegatePredicate!()(callback);
    }
}

private final class DelegatePredicate() : LongPredicate
{
    private bool delegate(long) @safe callback;

    this(bool delegate(long) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override bool test(long value)
    {
        return callback(value);
    }
}
