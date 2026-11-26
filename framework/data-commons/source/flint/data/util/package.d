// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/util/{Streamable,LazyStreamable}.java
// Streamable: Copyright 2016-present the original author or authors.
// LazyStreamable: Copyright 2017-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.util;

import flint.java.lang : IllegalArgumentException, Iterable, NullPointerException;
import flint.java.util : Iterator, List, Objects, Set;
import flint.java.util.function_ : Function, Predicate, Supplier;
import flint.java.util.stream : Collectors, Stream;

@safe:

/// Iterable values that can produce a fresh stream on each traversal (D-DATA-27).
interface Streamable(T) : Iterable!T, Supplier!(Stream!T)
{
    /// An empty source.
    static Streamable!T empty()
    {
        return of(() => Stream!T.empty());
    }

    /// A source over a copy of the supplied values.
    static Streamable!T of(T[] values...)
    {
        auto snapshot = values.dup;
        return of(() => Stream!T.ofArray(snapshot));
    }

    /// A source that obtains a fresh stream from the supplied factory.
    static Streamable!T of(Supplier!(Stream!T) supplier)
    {
        return of(supplier is null ? null : supplier.asDelegate());
    }

    /// Delegate overload for a stream factory (R9).
    static Streamable!T of(Stream!T delegate() @safe supplier)
    {
        return new LazyStreamable!T(supplier);
    }

    /// A fresh, sequential stream of the values.
    Stream!T stream();
    /// Whether the source contains no values.
    bool isEmpty();
    /// An unmodifiable list in encounter order.
    List!T toList();
    /// An unmodifiable set without duplicates.
    Set!T toSet();

    /// Concatenates a freshly supplied suffix to each traversal.
    Streamable!T and(Supplier!(Stream!T) supplier);
    /// Concatenates the supplied values.
    Streamable!T and(T[] others...);
    /// Concatenates another repeatable source.
    Streamable!T and(Streamable!T other);

    /// Concatenates zero values (D-DATA-27).
    final Streamable!T and()
    {
        return and(() => Stream!T.empty());
    }

    /// Delegate overload for a stream factory (R9).
    final Streamable!T and(Stream!T delegate() @safe supplier)
    {
        if (supplier is null)
            throw new IllegalArgumentException("Stream must not be null");
        auto source = this;
        return of(() => Stream!T.concat(source.stream(), Objects.requireNonNull(supplier(),
                "Stream must not be null")));
    }

    /// Transforms the values of each traversal.
    Streamable!R map(R)(Function!(T, R) mapper)
    {
        return map!R(mapper is null ? null : mapper.asDelegate());
    }

    /// Delegate overload for a value transform (R9).
    Streamable!R map(R)(R delegate(T) @safe mapper)
    {
        if (mapper is null)
            throw new IllegalArgumentException("Mapping function must not be null");
        auto source = this;
        return Streamable!R.of(() => source.stream().map!R(mapper));
    }

    /// Transforms each value to a stream and traverses the results in encounter order.
    Streamable!R flatMap(R)(Function!(T, Stream!R) mapper)
    {
        return flatMap!R(mapper is null ? null : mapper.asDelegate());
    }

    /// Delegate overload for a stream-producing transform (R9).
    Streamable!R flatMap(R)(Stream!R delegate(T) @safe mapper)
    {
        if (mapper is null)
            throw new IllegalArgumentException("Mapping function must not be null");
        auto source = this;
        return Streamable!R.of(() => source.stream().flatMap!R((T value) {
                auto mapped = mapper(value);
                return mapped is null ? Stream!R.empty() : mapped;
            }));
    }

    /// Retains the values matching the predicate in each traversal.
    Streamable!T filter(Predicate!T predicate);

    /// Delegate overload for a predicate (R9).
    final Streamable!T filter(bool delegate(T) @safe predicate)
    {
        if (predicate is null)
            throw new IllegalArgumentException("Filter predicate must not be null");
        auto source = this;
        return of(() => source.stream().filter(predicate));
    }

    /// Default operations for a repeatable stream source (R3).
    mixin template Defaults(Item = T)
    {
        override Streamable!Item and(Supplier!(Stream!Item) supplier)
        {
            return (cast(Streamable!Item) this).and(supplier is null ? null : supplier.asDelegate());
        }

        override Streamable!Item and(Item[] others...)
        {
            if (others is null)
                throw new IllegalArgumentException("Other values must not be null");
            auto snapshot = others.dup;
            return (cast(Streamable!Item) this).and(() => Stream!Item.ofArray(snapshot));
        }

        override Streamable!Item and(Streamable!Item other)
        {
            return (cast(Streamable!Item) this).and(cast(Supplier!(Stream!Item)) other);
        }

        override Streamable!Item filter(Predicate!Item predicate)
        {
            return (cast(Streamable!Item) this).filter(predicate is null ? null : predicate.asDelegate());
        }

        override Stream!Item get()
        {
            return stream();
        }

        override bool isEmpty()
        {
            return !iterator().hasNext();
        }

        override List!Item toList()
        {
            return stream().toList();
        }

        override Set!Item toSet()
        {
            return Set!Item.copyOf(stream().collect(Collectors.toSet()));
        }

        override void forEach(void delegate(Item) @safe action)
        {
            if (action is null)
                throw new NullPointerException("Action must not be null");
            foreach (value; this)
                action(value);
        }

        override int opApply(scope int delegate(Item) @safe visitor)
        {
            auto values = iterator();
            while (values.hasNext())
                if (const result = visitor(values.next()))
                    return result;
            return 0;
        }
    }
}

private final class LazyStreamable(T) : Streamable!T
{
    private Stream!T delegate() @safe factory;

    this(Stream!T delegate() @safe factory)
    {
        this.factory = factory;
    }

    mixin Streamable!T.Defaults;

    override Iterator!T iterator()
    {
        return stream().iterator();
    }

    override Stream!T stream()
    {
        if (factory is null)
            throw new NullPointerException("Stream supplier must not be null");
        return Objects.requireNonNull(factory(), "Stream must not be null");
    }
}
