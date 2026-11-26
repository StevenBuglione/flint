// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/util/{Streamable,LazyStreamable}.java
// Streamable: Copyright 2016-present the original author or authors.
// LazyStreamable: Copyright 2017-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.util;

import flint.java.lang : IllegalArgumentException, Iterable, NullPointerException;
import flint.java.util : Iterator, List, Objects, Set;
import flint.java.util.function_ : Supplier;
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

    /// Default traversal, concatenation and collection operations (R3).
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
