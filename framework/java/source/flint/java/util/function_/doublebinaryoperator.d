/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.doublebinaryoperator;

@safe:

/// Java's `DoubleBinaryOperator` contract (R9).
interface DoubleBinaryOperator
{
    /// Apply the operator to two doubles.
    double applyAsDouble(double left, double right);

    /// Call the operator through a D delegate.
    final double delegate(double, double) @safe asDelegate()
    {
        return &applyAsDouble;
    }

    /// R9 adapter. The caller instantiates the factory and owns its runtime type data.
    static DoubleBinaryOperator of()(double delegate(double, double) @safe callback)
    {
        return new DelegateOperator!()(callback);
    }
}

private final class DelegateOperator() : DoubleBinaryOperator
{
    private double delegate(double, double) @safe callback;

    this(double delegate(double, double) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override double applyAsDouble(double left, double right)
    {
        return callback(left, right);
    }
}
