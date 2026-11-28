/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.doubleunaryoperator;

@safe:

/// Java's `DoubleUnaryOperator` contract (R9).
interface DoubleUnaryOperator
{
    /// Apply the operator to `value`.
    double applyAsDouble(double value);

    /// Call the operator through a D delegate.
    final double delegate(double) @safe asDelegate()
    {
        return &applyAsDouble;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static DoubleUnaryOperator of()(double delegate(double) @safe callback)
    {
        return new DelegateOperator!()(callback);
    }
}

private final class DelegateOperator() : DoubleUnaryOperator
{
    private double delegate(double) @safe callback;

    this(double delegate(double) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override double applyAsDouble(double value)
    {
        return callback(value);
    }
}
