/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.intunaryoperator;

@safe:

/// Java's `IntUnaryOperator` contract (R9).
interface IntUnaryOperator
{
    /// Apply the operator to `value`.
    int applyAsInt(int value);

    /// Call the operator through a D delegate.
    final int delegate(int) @safe asDelegate()
    {
        return &applyAsInt;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static IntUnaryOperator of()(int delegate(int) @safe callback)
    {
        return new DelegateOperator!()(callback);
    }
}

private final class DelegateOperator() : IntUnaryOperator
{
    private int delegate(int) @safe callback;

    this(int delegate(int) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override int applyAsInt(int value)
    {
        return callback(value);
    }
}
