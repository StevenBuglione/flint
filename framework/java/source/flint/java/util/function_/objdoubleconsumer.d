/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.objdoubleconsumer;

@safe:

/// Java's `ObjDoubleConsumer` contract (R9).
interface ObjDoubleConsumer(T)
{
    /// Perform the operation on `object` and `value`.
    void accept(T object, double value);

    /// Call the consumer through a D delegate.
    final void delegate(T, double) @safe asDelegate()
    {
        return &accept;
    }

    /// Adapt a typed D delegate at its call site.
    static ObjDoubleConsumer!T of()(void delegate(T, double) @safe callback)
    {
        return new DelegateConsumer!T(callback);
    }
}

private final class DelegateConsumer(T) : ObjDoubleConsumer!T
{
    private void delegate(T, double) @safe callback;

    this(void delegate(T, double) @safe callback) pure nothrow @nogc
    {
        this.callback = callback;
    }

    override void accept(T object, double value)
    {
        callback(object, value);
    }
}
