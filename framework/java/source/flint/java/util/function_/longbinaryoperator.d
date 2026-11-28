/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.longbinaryoperator;

@safe:

/// Java's `LongBinaryOperator` contract (R9).
interface LongBinaryOperator
{
    /// Apply the operator to two longs.
    long applyAsLong(long left, long right);

    /// Call the operator through a D delegate.
    final long delegate(long, long) @safe asDelegate()
    {
        return &applyAsLong;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static LongBinaryOperator of()(long delegate(long, long) @safe callback)
    {
        return new DelegateOperator!()(callback);
    }
}

private final class DelegateOperator() : LongBinaryOperator
{
    private long delegate(long, long) @safe callback;

    this(long delegate(long, long) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override long applyAsLong(long left, long right)
    {
        return callback(left, right);
    }
}
