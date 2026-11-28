/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.objintconsumer;

@safe:

/// Java's `ObjIntConsumer` contract (R9).
interface ObjIntConsumer(T)
{
    /// Perform the operation on `object` and `value`.
    void accept(T object, int value);

    /// Call the consumer through a D delegate.
    final void delegate(T, int) @safe asDelegate()
    {
        return &accept;
    }

    /// Adapt a typed D delegate at its call site.
    static ObjIntConsumer!T of()(void delegate(T, int) @safe callback)
    {
        return new DelegateConsumer!T(callback);
    }
}

private final class DelegateConsumer(T) : ObjIntConsumer!T
{
    private void delegate(T, int) @safe callback;

    this(void delegate(T, int) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override void accept(T object, int value)
    {
        callback(object, value);
    }
}
