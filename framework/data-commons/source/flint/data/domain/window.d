// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/domain/{Window,WindowImpl}.java
// Copyright 2023-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.domain.window;

import flint.data.domain.scroll_position : ScrollPosition;
import flint.java.lang : IllegalArgumentException, IllegalStateException, IndexOutOfBoundsException,
    Iterable, JavaObject;
import flint.java.util : ArrayList, Iterator, List, NoSuchElementException, Objects;
import flint.java.util.function_ : Function, IntFunction;

@safe:

private alias PositionDelegate = ScrollPosition delegate(int) @safe;

/// A batch of query results with positions for resuming the scroll.
interface Window(T) : Iterable!T
{
    /// A window over a list and an indexed position function.
    static Window!T from(P)(List!T items, IntFunction!P positions, bool hasNext = false)
            if (is(P : ScrollPosition))
    {
        if (positions is null)
            throw new IllegalArgumentException("Position function must not be null");
        return new WindowImpl!T(items, PositionLookup(cast(Object) positions, &lookupPosition!P), hasNext);
    }

    /// A window over a list and an indexed position delegate (R9).
    static Window!T from(List!T items, PositionDelegate positions, bool hasNext = false)
    {
        if (positions is null)
            throw new IllegalArgumentException("Position function must not be null");
        return new WindowImpl!T(items, PositionLookup(null, null, positions), hasNext);
    }

    /// Number of results in this window.
    int size();

    /// Whether the window is empty.
    bool isEmpty();

    /// The list backing the window.
    List!T getContent();

    /// Whether this is the last window in the scroll.
    bool isLast();

    /// Whether another window can follow this one.
    bool hasNext();

    /// Whether a position is available at `index`. Invalid indexes still throw.
    bool hasPosition(int index);

    /// The position at a zero-based index.
    ScrollPosition positionAt(int index);

    static if (is(T == int))
    {
        /// The position of the first matching integer item. Call as `positionAt!int(item)`.
        ScrollPosition positionAt(U)(T item) if (is(U == T))
        {
            return positionOf(item);
        }
    }
    else
    {
        /// The position of the first matching item.
        ScrollPosition positionAt(T item);
    }

    private final ScrollPosition positionOf(T item)
    {
        const index = getContent().indexOf(item);
        if (index == -1)
            throw new NoSuchElementException();
        return positionAt(index);
    }

    /// A window with the same positions and continuation, containing converted items.
    Window!U map(U)(U delegate(T) @safe converter)
    {
        if (converter is null)
            throw new IllegalArgumentException("Function must not be null");
        auto items = new ArrayList!U(size());
        foreach (item; this)
            items.add(converter(item));

        if (auto concrete = cast(WindowImpl!T) this)
            return new WindowImpl!U(items, concrete.positions, hasNext());
        return Window!U.from(items, &positionAt, hasNext());
    }

    /// Map the window using a Java function object.
    Window!U map(U)(Function!(T, U) converter)
    {
        if (converter is null)
            throw new IllegalArgumentException("Function must not be null");
        return map(converter.asDelegate());
    }

    /// Defaults for implementations of the window interface (R3).
    mixin template Defaults()
    {
        static if (!is(T == int))
        {
            ScrollPosition positionAt(T item)
            {
                return (cast(Window!T) this).positionOf(item);
            }
        }

        bool isLast()
        {
            return !(cast(Window!T) this).hasNext();
        }

        bool hasPosition(int index)
        {
            try
            {
                (cast(Window!T) this).positionAt(index);
                return true;
            }
            catch (IllegalStateException)
            {
                return false;
            }
        }
    }
}

// Keep the original function object for equality without wrapping it in an allocated closure.
private struct PositionLookup
{
    Object source;
    ScrollPosition function(Object, int) @safe apply;
    PositionDelegate callback;

    ScrollPosition at(int index)
    {
        return source is null ? callback(index) : apply(source, index);
    }

    bool equals(PositionLookup other)
    {
        return callback == other.callback && Objects.equals(source, other.source);
    }

    int hashCode()
    {
        return source is null ? Objects.hashCode(callback) : Objects.hashCode(source);
    }
}

private ScrollPosition lookupPosition(P)(Object source, int index)
{
    return (cast(IntFunction!P) source).apply(index);
}

private final class WindowImpl(T) : Window!T
{
    private List!T items;
    private PositionLookup positions;
    private const bool hasNext_;

    this(List!T items, PositionLookup positions, bool hasNext)
    {
        if (items is null)
            throw new IllegalArgumentException("List of items must not be null");
        this.items = items;
        this.positions = positions;
        hasNext_ = hasNext;
    }

    mixin Window!T.Defaults defaults;
    alias isLast = defaults.isLast;
    alias hasPosition = defaults.hasPosition;
    static if (!is(T == int))
        alias positionAt = defaults.positionAt;

    override int size()
    {
        return items.size();
    }

    override bool isEmpty()
    {
        return items.isEmpty();
    }

    override List!T getContent()
    {
        return items;
    }

    override bool hasNext()
    {
        return hasNext_;
    }

    override ScrollPosition positionAt(int index)
    {
        if (index < 0 || index >= size())
            throw new IndexOutOfBoundsException(index);
        return positions.at(index);
    }

    override Iterator!T iterator()
    {
        return items.iterator();
    }

    mixin Iterable!T.Defaults;

    override int opApply(scope int delegate(T) @safe dg)
    {
        return items.opApply(dg);
    }

    bool equals(Object other)
    {
        auto that = cast(WindowImpl!T) other;
        return this is other || (that !is null && hasNext_ == that.hasNext_
                && positions.equals(that.positions) && Objects.equals(items, that.items));
    }

    int hashCode()
    {
        return 31 * (31 * items.hashCode() + positions.hashCode()) + Objects.hashCode(hasNext_);
    }

    override string toString()
    {
        return "Window " ~ items.toString();
    }

    mixin JavaObject;
}
