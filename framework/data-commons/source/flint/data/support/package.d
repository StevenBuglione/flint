// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/support/WindowIterator.java
// Copyright 2023-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.support;

import flint.data.domain.scroll_position : KeysetScrollPosition, ScrollPosition;
import flint.data.domain.window : Window;
import flint.java.lang : IllegalArgumentException, NullPointerException, UnsupportedOperationException;
import flint.java.util : Iterator, List, NoSuchElementException;
import flint.java.util.function_ : Function;
public import flint.data.support.is_new_strategy : IsNewStrategy, PersistableIsNewStrategy;
public import flint.data.support.pageable_execution_utils : PageableExecutionUtils;

@safe:

/// An iterator across windows obtained on demand from successive scroll positions.
class WindowIterator(T) : Iterator!T
{
    private alias WindowFunction = Window!T delegate(ScrollPosition) @safe;

    private WindowFunction fetchWindow;
    private ScrollPosition position;
    private Window!T window;
    private Iterator!T iterator;

    private this(WindowFunction fetchWindow, ScrollPosition position)
    {
        this.fetchWindow = fetchWindow;
        this.position = position;
    }

    /// Set the function that fetches each window.
    static WindowIteratorBuilder of(Function!(ScrollPosition, Window!T) fetchWindow)
    {
        if (fetchWindow is null)
            throw new IllegalArgumentException("WindowFunction must not be null");
        return of(fetchWindow.asDelegate());
    }

    /// Set the delegate that fetches each window (R9).
    static WindowIteratorBuilder of(WindowFunction fetchWindow)
    {
        if (fetchWindow is null)
            throw new IllegalArgumentException("WindowFunction must not be null");
        return new WindowIteratorBuilder(fetchWindow);
    }

    /// Fetch another window only after the current one is consumed.
    override bool hasNext()
    {
        while (true)
        {
            if (window is null)
            {
                window = fetchWindow(position);
                if (window is null)
                    throw new NullPointerException("Window function returned null");
            }

            if (iterator is null)
            {
                const backward = scrollsBackward(position);
                iterator = backward ? new ReverseListIterator!T(window.getContent()) : window.iterator();
            }
            if (iterator.hasNext())
                return true;
            if (!window.hasNext())
                return false;

            position = window.positionAt(scrollsBackward(position) ? 0 : window.size() - 1);
            window = null;
            iterator = null;
        }
    }

    /// The next result. Throws NoSuchElementException after the scroll is exhausted.
    override T next()
    {
        if (!hasNext())
            throw new NoSuchElementException();
        return iterator.next();
    }

    /// Window iteration does not support removal.
    override void remove()
    {
        throw new UnsupportedOperationException();
    }

    /// Builds a fresh iterator for a starting position.
    static class WindowIteratorBuilder
    {
        private WindowFunction fetchWindow;

        private this(WindowFunction fetchWindow)
        {
            this.fetchWindow = fetchWindow;
        }

        /// Start the scroll at `position`.
        WindowIterator!T startingAt(ScrollPosition position)
        {
            if (position is null)
                throw new IllegalArgumentException("ScrollPosition must not be null");
            return new WindowIterator!T(fetchWindow, position);
        }
    }
}

private bool scrollsBackward(ScrollPosition position)
{
    auto keyset = cast(KeysetScrollPosition) position;
    return keyset !is null && keyset.scrollsBackward();
}

private final class ReverseListIterator(T) : Iterator!T
{
    private List!T list;
    private int remaining;

    this(List!T list)
    {
        this.list = list;
        remaining = list.size();
    }

    override bool hasNext()
    {
        return remaining > 0;
    }

    override T next()
    {
        if (!hasNext())
            throw new NoSuchElementException();
        auto item = list.get(remaining - 1);
        --remaining;
        return item;
    }

    override void remove()
    {
        throw new UnsupportedOperationException();
    }
}
