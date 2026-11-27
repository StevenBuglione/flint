/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */

/++
Java's `Collector` (rulebook R3, R9, R13): a mutable reduction that `Stream.collect` drives. The structs of `Collectors`
need none of it, so a program that never names `Collector` does not link this module.
+/
module flint.java.util.stream.collector;

import flint.java.util : Set;
import flint.java.util.function_ : BiConsumer, BinaryOperator, Function, Supplier;

@safe:

/// Java's `Collector.Characteristics`, hoisted out of the generic interface (R13) and aliased back as
/// `Collector!(T, A, R).Characteristics`.
enum Characteristics
{
    /// The container may be accumulated into from several threads.
    CONCURRENT,
    /// The result does not depend on encounter order.
    UNORDERED,
    /// The finisher is the identity, so the container is the result.
    IDENTITY_FINISH,
}

/// Java's `Collector`: a supplier of mutable containers, an accumulator, a combiner and a finisher.
interface Collector(T, A, R)
{
    /// Java's `Collector.Characteristics`.
    alias Characteristics = .Characteristics;

    /// Makes a new container.
    Supplier!A supplier();

    /// Adds an element to a container.
    BiConsumer!(A, T) accumulator();

    /// Merges two containers.
    BinaryOperator!A combiner();

    /// Turns a container into the result.
    Function!(A, R) finisher();

    /// This collector's characteristics.
    Set!Characteristics characteristics();

    /// A collector of the four functions. A null function throws `NullPointerException`; a null `characteristics`
    /// array counts as empty (R26).
    static Collector!(T, A, R) of(Supplier!A supplier, BiConsumer!(A, T) accumulator,
            BinaryOperator!A combiner, Function!(A, R) finisher, Characteristics[] characteristics...)
    {
        requireFunction(supplier);
        requireFunction(accumulator);
        requireFunction(combiner);
        requireFunction(finisher);
        return new FunctionCollector!(T, A, R)(supplier, accumulator, combiner, finisher,
                characteristicSet(characteristics, false));
    }

    /// A collector of the four delegates (R9).
    static Collector!(T, A, R) of(A delegate() @safe supplier, void delegate(A, T) @safe accumulator,
            A delegate(A, A) @safe combiner, R delegate(A) @safe finisher, Characteristics[] characteristics...)
    {
        return of(Supplier!A.of(requireFunction(supplier)), BiConsumer!(A, T)
                .of(requireFunction(accumulator)), new DelegateBinaryOperator!A(requireFunction(combiner)),
                Function!(A, R).of(requireFunction(finisher)), characteristics);
    }

    static if (is(A == R))
    {
        /// A collector whose container is its result, so its characteristics include `IDENTITY_FINISH`.
        static Collector!(T, A, R) of(Supplier!A supplier, BiConsumer!(A, T) accumulator,
                BinaryOperator!A combiner, Characteristics[] characteristics...)
        {
            requireFunction(supplier);
            requireFunction(accumulator);
            requireFunction(combiner);
            return new FunctionCollector!(T, A, R)(supplier, accumulator, combiner, Function!(A,
                    A).identity(), characteristicSet(characteristics, true));
        }

        /// The same of three delegates (R9).
        static Collector!(T, A, R) of(A delegate() @safe supplier, void delegate(A,
                T) @safe accumulator, A delegate(A, A) @safe combiner, Characteristics[] characteristics...)
        {
            return of(Supplier!A.of(requireFunction(supplier)), BiConsumer!(A, T)
                    .of(requireFunction(accumulator)),
                    new DelegateBinaryOperator!A(requireFunction(combiner)), characteristics);
        }
    }
}

private F requireFunction(F)(F function_)
{
    if (function_ is null)
        throwNullFunction();
    return function_;
}

pragma(inline, false) private noreturn throwNullFunction()
{
    import flint.java.lang : NullPointerException;

    throw new NullPointerException();
}

/// The unmodifiable set of `characteristics` in declaration order, as Java's `EnumSet` iterates, over a bit mask (S-149).
/// A template, so the library itself never instantiates the set (and its enum formatting) for programs that do not
/// call `of`.
private Set!Characteristics characteristicSet()(scope Characteristics[] characteristics, bool identityFinish)
{
    import flint.java.util.internal.enumbitset : EnumBitSet;

    if (identityFinish)
        return EnumBitSet!Characteristics.of(characteristics ~ Characteristics.IDENTITY_FINISH);
    return EnumBitSet!Characteristics.of(characteristics);
}

private final class FunctionCollector(T, A, R) : Collector!(T, A, R)
{
    private Supplier!A supplier_;
    private BiConsumer!(A, T) accumulator_;
    private BinaryOperator!A combiner_;
    private Function!(A, R) finisher_;
    private Set!Characteristics characteristics_;

    this(Supplier!A supplier, BiConsumer!(A, T) accumulator, BinaryOperator!A combiner,
            Function!(A, R) finisher, Set!Characteristics characteristics)
    {
        supplier_ = supplier;
        accumulator_ = accumulator;
        combiner_ = combiner;
        finisher_ = finisher;
        characteristics_ = characteristics;
    }

    Supplier!A supplier()
    {
        return supplier_;
    }

    BiConsumer!(A, T) accumulator()
    {
        return accumulator_;
    }

    BinaryOperator!A combiner()
    {
        return combiner_;
    }

    Function!(A, R) finisher()
    {
        return finisher_;
    }

    Set!Characteristics characteristics()
    {
        return characteristics_;
    }
}

private final class DelegateBinaryOperator(T) : BinaryOperator!T
{
    private T delegate(T, T) @safe dg;

    this(T delegate(T, T) @safe dg) pure nothrow @nogc
    {
        this.dg = dg;
    }

    T apply(T left, T right)
    {
        return dg(left, right);
    }
}

/++
`Stream.collect` with a `Collector`, in Java's order: the supplier, accumulator and combiner are fetched before the
stream is taken, the characteristics are read once before traversal and once after, and the finisher is skipped under
`IDENTITY_FINISH`. A null collector or a null function throws `NullPointerException` where Java's would.
+/
package R collectWith(T, A, R)(Collector!(T, A, R) collector, scope bool delegate(out T) @safe delegate() @safe take)
{
    if (collector is null)
        throwNullFunction();
    auto supplier = collector.supplier();
    auto accumulator = collector.accumulator();
    collector.combiner();
    auto source = take();
    cast(void) identityFinish(collector);
    A container = requireFunction(supplier).get();
    T next;
    if (source(next))
    {
        requireFunction(accumulator);
        do
            accumulator.accept(container, next);
        while (source(next));
    }
    if (identityFinish(collector))
        return finishByCast!R(container);
    return requireFunction(collector.finisher()).apply(container);
}

private bool identityFinish(T, A, R)(Collector!(T, A, R) collector)
{
    return requireFunction(collector.characteristics()).contains(Characteristics.IDENTITY_FINISH);
}

/// Java's unchecked cast of the container to the result type under `IDENTITY_FINISH`.
private R finishByCast(R, A)(A container)
{
    static if (is(A : R))
        return container;
    else static if ((is(A == class) || is(A == interface)) && (is(R == class) || is(R == interface)))
    {
        import flint.java.lang : ClassCastException;

        auto result = cast(R) container;
        if (result is null && container !is null)
            throw new ClassCastException("class " ~ typeid(container).name ~ " cannot be cast to " ~ R.stringof);
        return result;
    }
    else
    {
        import flint.java.lang : ClassCastException;

        throw new ClassCastException(A.stringof ~ " cannot be cast to " ~ R.stringof);
    }
}
