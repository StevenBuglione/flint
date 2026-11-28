// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module queue_leaf_test;

import flint.java.lang : IllegalStateException;
import flint.java.util : AbstractCollection, Collection, Iterator, NoSuchElementException, RawCollection;
import flint.java.util.queue : Queue;

@safe:

private final class ArrayQueue(T) : AbstractCollection!T, Queue!T
{
    private T[] items;
    private int head;

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
        return cast(int)(items.length - head);
    }

    override bool add(T e)
    {
        return offer(e);
    }

    bool offer(T e)
    {
        items ~= e;
        return true;
    }

    T remove()
    {
        if (isEmpty())
            throw new NoSuchElementException();
        return poll();
    }

    T poll()
    {
        if (isEmpty())
            return T.init;
        auto result = items[head++];
        if (head == items.length)
        {
            items = null;
            head = 0;
        }
        return result;
    }

    T element()
    {
        if (isEmpty())
            throw new NoSuchElementException();
        return items[head];
    }

    T peek()
    {
        return isEmpty() ? T.init : items[head];
    }

    override Iterator!T iterator()
    {
        return new Cursor(this);
    }

    private final class Cursor : Iterator!T
    {
        private ArrayQueue!T owner;
        private int index;
        private int last = -1;

        this(ArrayQueue!T owner) pure nothrow @nogc
        {
            this.owner = owner;
            this.index = owner.head;
        }

        bool hasNext()
        {
            return index < owner.items.length;
        }

        T next()
        {
            if (!hasNext())
                throw new NoSuchElementException();
            last = index;
            return owner.items[index++];
        }

        void remove()
        {
            if (last < 0)
                throw new IllegalStateException();
            owner.items = owner.items[0 .. last] ~ owner.items[last + 1 .. $];
            index = last;
            last = -1;
        }
    }
}

@("Queue keeps Collection identity and both remove overloads")
unittest
{
    Queue!int queue = new ArrayQueue!int();
    Collection!int collection = queue;
    auto erased = cast(RawCollection) queue;
    assert(cast(Queue!int) collection is queue && cast(Queue!int) erased is queue);

    assert(queue.isEmpty() && queue.size() == 0);
    assert(queue.poll() == 0 && queue.peek() == 0);

    assert(queue.offer(1));
    assert(collection.add(2));
    assert(queue.offer(3));
    assert(queue.size() == 3 && queue.peek() == 1 && queue.element() == 1);

    assert(queue.remove(2));
    assert(!queue.remove(2));
    assert(queue.size() == 2);

    assert(queue.poll() == 1);
    assert(queue.remove() == 3);
    assert(queue.isEmpty() && queue.poll() == 0);
}

@("Queue's throwing operations report an empty queue")
unittest
{
    Queue!int queue = new ArrayQueue!int();
    bool removed, elemented;
    try
        queue.remove();
    catch (NoSuchElementException)
        removed = true;
    try
        queue.element();
    catch (NoSuchElementException)
        elemented = true;
    assert(removed && elemented);
}

@("Queue of a reference type returns null when empty")
unittest
{
    Queue!string queue = new ArrayQueue!string();
    assert(queue.poll() is null && queue.peek() is null);
    assert(queue.offer("first"));
    assert(queue.peek() == "first");
    assert(queue.poll() == "first");
    assert(queue.peek() is null);
}
