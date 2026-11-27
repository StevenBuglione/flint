/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.doubleconsumer;

@safe:

/// Java's double-valued consumer contract (R9).
interface DoubleConsumer
{
    /// Perform the operation on value.
    void accept(double value);

    /// Call the consumer through a D delegate.
    final void delegate(double) @safe asDelegate()
    {
        return &accept;
    }

    /// Adapt a typed D delegate at its call site.
    static DoubleConsumer of()(void delegate(double) @safe callback)
    {
        return new DelegateConsumer!()(callback);
    }
}

private final class DelegateConsumer() : DoubleConsumer
{
    private void delegate(double) @safe callback;

    this(void delegate(double) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override void accept(double value)
    {
        callback(value);
    }
}
