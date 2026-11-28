// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module deque_leaf_test;

import flint.java.lang : IllegalStateException, javaEquals;
import flint.java.util : AbstractCollection, Collection, Iterator, NoSuchElementException, RawCollection;
import flint.java.util.deque : Deque;
import flint.java.util.queue : Queue;

@safe:

private final class TestDeque(T) : AbstractCollection!T, Deque!T
{
    private T[] items;

    bool equals(Object o)
    {
        return o is this;
    }

    int hashCode()
    {
        return cast(int)(cast(size_t) cast(const(void)*) this);
    }

    override int size()
    {
        return cast(int) items.length;
    }

    override bool add(T e)
    {
        items ~= e;
        return true;
    }

    bool offer(T e)
    {
        items ~= e;
        return true;
    }

    alias remove = AbstractCollection!T.remove;

    T remove()
    {
        return removeFirst();
    }

    T poll()
    {
        return pollFirst();
    }

    T element()
    {
        return getFirst();
    }

    T peek()
    {
        return peekFirst();
    }

    void addFirst(T e)
    {
        items = e ~ items;
    }

    void addLast(T e)
    {
        items ~= e;
    }

    bool offerFirst(T e)
    {
        items = e ~ items;
        return true;
    }

    bool offerLast(T e)
    {
        items ~= e;
        return true;
    }

    T removeFirst()
    {
        if (items.length == 0)
            throw new NoSuchElementException();
        auto result = items[0];
        items = items[1 .. $];
        return result;
    }

    T removeLast()
    {
        if (items.length == 0)
            throw new NoSuchElementException();
        auto result = items[$ - 1];
        items = items[0 .. $ - 1];
        return result;
    }

    T pollFirst()
    {
        return items.length == 0 ? T.init : removeFirst();
    }

    T pollLast()
    {
        return items.length == 0 ? T.init : removeLast();
    }

    T getFirst()
    {
        if (items.length == 0)
            throw new NoSuchElementException();
        return items[0];
    }

    T getLast()
    {
        if (items.length == 0)
            throw new NoSuchElementException();
        return items[$ - 1];
    }

    T peekFirst()
    {
        return items.length == 0 ? T.init : items[0];
    }

    T peekLast()
    {
        return items.length == 0 ? T.init : items[$ - 1];
    }

    bool removeFirstOccurrence(T o)
    {
        foreach (i, e; items)
            if (javaEquals(e, o))
            {
                items = items[0 .. i] ~ items[i + 1 .. $];
                return true;
            }
        return false;
    }

    bool removeLastOccurrence(T o)
    {
        for (int i = cast(int) items.length - 1; i >= 0; i--)
            if (javaEquals(items[i], o))
            {
                items = items[0 .. i] ~ items[i + 1 .. $];
                return true;
            }
        return false;
    }

    void push(T e)
    {
        addFirst(e);
    }

    T pop()
    {
        return removeFirst();
    }

    override Iterator!T iterator()
    {
        return new Cursor(this, false);
    }

    Iterator!T descendingIterator()
    {
        return new Cursor(this, true);
    }

    private final class Cursor : Iterator!T
    {
        private TestDeque!T owner;
        private int index;
        private int last = -1;
        private bool reverse;

        this(TestDeque!T owner, bool reverse) pure nothrow @nogc
        {
            this.owner = owner;
            this.reverse = reverse;
            this.index = reverse ? cast(int) owner.items.length - 1 : 0;
        }

        bool hasNext()
        {
            return reverse ? index >= 0 : index < owner.items.length;
        }

        T next()
        {
            if (!hasNext())
                throw new NoSuchElementException();
            last = index;
            auto result = owner.items[index];
            index += reverse ? -1 : 1;
            return result;
        }

        void remove()
        {
            if (last < 0)
                throw new IllegalStateException();
            owner.items = owner.items[0 .. last] ~ owner.items[last + 1 .. $];
            index = reverse ? last - 1 : last;
            last = -1;
        }
    }
}

@("Deque is a Queue and keeps Collection identity")
unittest
{
    static assert(is(Deque!int : Queue!int));
    static assert(is(Deque!int : Collection!int));

    Deque!int deque = new TestDeque!int();
    auto queue = cast(Queue!int) deque;
    auto collection = cast(Collection!int) deque;
    auto erased = cast(RawCollection) deque;
    assert(cast(Deque!int) queue is deque && cast(Deque!int) collection is deque && cast(Deque!int) erased is deque);
}

@("Deque's ends, stack operations and descending iterator")
unittest
{
    Deque!int deque = new TestDeque!int();
    assert(deque.isEmpty() && deque.size() == 0);
    assert(deque.pollFirst() == 0 && deque.pollLast() == 0 && deque.peekFirst() == 0 && deque.peekLast() == 0);

    deque.addLast(2);
    deque.addFirst(1);
    deque.offerLast(3);
    deque.offerFirst(0);
    assert(deque.toArray() == [0, 1, 2, 3]);
    assert(deque.getFirst() == 0 && deque.getLast() == 3);
    assert(deque.peekFirst() == 0 && deque.peekLast() == 3);

    assert(deque.removeFirst() == 0);
    assert(deque.removeLast() == 3);
    assert(deque.pollFirst() == 1);
    assert(deque.pollLast() == 2);
    assert(deque.isEmpty());

    deque.push(9);
    deque.push(8);
    assert(deque.toArray() == [8, 9]);
    assert(deque.pop() == 8 && deque.pop() == 9);

    deque.addLast(1);
    deque.addLast(2);
    deque.addLast(3);
    auto descending = deque.descendingIterator();
    int[] seen;
    while (descending.hasNext())
        seen ~= descending.next();
    assert(seen == [3, 2, 1]);
}

@("Deque's occurrence removal and empty-queue throws")
unittest
{
    Deque!int deque = new TestDeque!int();
    deque.addLast(1);
    deque.addLast(2);
    deque.addLast(1);
    deque.addLast(1);
    assert(deque.removeFirstOccurrence(1));
    assert(deque.toArray() == [2, 1, 1]);
    assert(deque.removeLastOccurrence(1));
    assert(deque.toArray() == [2, 1]);
    assert(!deque.removeFirstOccurrence(7));

    bool first, last, getFirst, getLast, pop;
    try
    {
        deque.clear();
        deque.removeFirst();
    }
    catch (NoSuchElementException)
        first = true;
    try
        deque.removeLast();
    catch (NoSuchElementException)
        last = true;
    try
        deque.getFirst();
    catch (NoSuchElementException)
        getFirst = true;
    try
        deque.getLast();
    catch (NoSuchElementException)
        getLast = true;
    try
        deque.pop();
    catch (NoSuchElementException)
        pop = true;
    assert(first && last && getFirst && getLast && pop);
}

@("Deque.reversed is a live view with swapped ends")
unittest
{
    Deque!int deque = new TestDeque!int();
    deque.addLast(1);
    deque.addLast(2);
    deque.addLast(3);

    auto reversed = deque.reversed();
    assert(reversed.getFirst() == 3 && reversed.getLast() == 1);
    assert(reversed.peekFirst() == 3 && reversed.peekLast() == 1);
    assert(reversed.toArray() == [3, 2, 1]);
    assert(reversed.reversed() is deque);

    deque.addLast(4);
    assert(reversed.getFirst() == 4);

    reversed.addFirst(0);
    assert(deque.getLast() == 0);
    reversed.addLast(5);
    assert(deque.getFirst() == 5);

    assert(reversed.removeFirst() == 0);
    assert(deque.getLast() == 4);
    assert(reversed.removeLast() == 5);
    assert(deque.getFirst() == 1);

    assert(reversed.pollFirst() == 4);
    assert(reversed.pollLast() == 1);
    assert(reversed.toArray() == [3, 2]);

    reversed.push(9);
    assert(deque.toArray() == [2, 3, 9]);
    assert(reversed.pop() == 9);

    auto descending = reversed.descendingIterator();
    int[] seen;
    while (descending.hasNext())
        seen ~= descending.next();
    assert(seen == [2, 3]);

    reversed.addFirst(1);
    reversed.addFirst(1);
    assert(reversed.removeFirstOccurrence(1));
    assert(deque.toArray() == [2, 3, 1]);
    assert(reversed.removeLastOccurrence(1));
    assert(deque.toArray() == [2, 3]);

    assert(reversed.size() == deque.size() && reversed.contains(2));
    assert(reversed.toString() == "[3, 2]");
}
