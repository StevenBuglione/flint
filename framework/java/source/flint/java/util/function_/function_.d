/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

module flint.java.util.function_.function_;

@safe:

/// Java's `Function`: a one-argument function.
interface Function(T, R)
{
    /// Apply the function to `t`.
    R apply(T t);

    /// The `apply` method as a delegate.
    final R delegate(T) @safe asDelegate()
    {
        return &apply;
    }

    /// First this function, then `after`.
    Function!(T, V) andThen(V)(Function!(R, V) after)
    {
        auto self = this;
        return Function!(T, V).of((T t) => after.apply(self.apply(t)));
    }

    /// First `before`, then this function.
    Function!(V, R) compose(V)(Function!(V, T) before)
    {
        auto self = this;
        return Function!(V, R).of((V v) => self.apply(before.apply(v)));
    }

    /// A `Function` calling `dg`.
    static Function!(T, R) of(R delegate(T) @safe dg)
    {
        return new DelegateFunction!(T, R)(dg);
    }

    /// The identity function (when `T` and `R` are the same type).
    static if (is(T == R))
    {
        /// Java's `Function.identity()`.
        static Function!(T, T) identity()
        {
            return of((T t) => t);
        }
    }
}

private final class DelegateFunction(T, R) : Function!(T, R)
{
    private R delegate(T) @safe dg;

    this(R delegate(T) @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    R apply(T t)
    {
        return dg(t);
    }
}
