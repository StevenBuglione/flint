/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.longconsumer;

@safe:

/// Java's long-valued consumer contract (R9).
interface LongConsumer
{
    /// Perform the operation on value.
    void accept(long value);

    /// Call the consumer through a D delegate.
    final void delegate(long) @safe asDelegate()
    {
        return &accept;
    }

    /// Adapt a typed D delegate at its call site.
    static LongConsumer of()(void delegate(long) @safe callback)
    {
        return new DelegateConsumer!()(callback);
    }
}

private final class DelegateConsumer() : LongConsumer
{
    private void delegate(long) @safe callback;

    this(void delegate(long) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override void accept(long value)
    {
        callback(value);
    }
}
