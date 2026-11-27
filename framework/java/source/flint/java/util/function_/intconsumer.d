/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.intconsumer;

@safe:

/// Java's int-valued consumer contract (R9).
interface IntConsumer
{
    /// Perform the operation on value.
    void accept(int value);

    /// Call the consumer through a D delegate.
    final void delegate(int) @safe asDelegate()
    {
        return &accept;
    }

    /// Adapt a typed D delegate at its call site.
    static IntConsumer of()(void delegate(int) @safe callback)
    {
        return new DelegateConsumer!()(callback);
    }
}

private final class DelegateConsumer() : IntConsumer
{
    private void delegate(int) @safe callback;

    this(void delegate(int) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override void accept(int value)
    {
        callback(value);
    }
}
