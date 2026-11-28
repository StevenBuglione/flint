/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.longunaryoperator;

@safe:

/// Java's `LongUnaryOperator` contract (R9).
interface LongUnaryOperator
{
    /// Apply the operator to `value`.
    long applyAsLong(long value);

    /// Call the operator through a D delegate.
    final long delegate(long) @safe asDelegate()
    {
        return &applyAsLong;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static LongUnaryOperator of()(long delegate(long) @safe callback)
    {
        return new DelegateOperator!()(callback);
    }
}

private final class DelegateOperator() : LongUnaryOperator
{
    private long delegate(long) @safe callback;

    this(long delegate(long) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override long applyAsLong(long value)
    {
        return callback(value);
    }
}
