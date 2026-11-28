/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.objlongconsumer;

@safe:

/// Java's `ObjLongConsumer` contract (R9).
interface ObjLongConsumer(T)
{
    /// Perform the operation on `object` and `value`.
    void accept(T object, long value);

    /// Call the consumer through a D delegate.
    final void delegate(T, long) @safe asDelegate()
    {
        return &accept;
    }

    /// Adapt a typed D delegate at its call site.
    static ObjLongConsumer!T of()(void delegate(T, long) @safe callback)
    {
        return new DelegateConsumer!T(callback);
    }
}

private final class DelegateConsumer(T) : ObjLongConsumer!T
{
    private void delegate(T, long) @safe callback;

    this(void delegate(T, long) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override void accept(T object, long value)
    {
        callback(object, value);
    }
}
