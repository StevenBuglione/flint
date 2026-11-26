/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.supplier;

@safe:

/// Java's `Supplier`: a source of results.
interface Supplier(T)
{
    /// A result.
    T get();

    /// The `get` method as a delegate.
    final T delegate() @safe asDelegate()
    {
        return &get;
    }

    /// A `Supplier` calling `dg`.
    static Supplier!T of(T delegate() @safe dg)
    {
        return new DelegateSupplier!(T)(dg);
    }
}

private final class DelegateSupplier(T) : Supplier!(T)
{
    private T delegate() @safe dg;

    this(T delegate() @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    T get()
    {
        return dg();
    }
}
