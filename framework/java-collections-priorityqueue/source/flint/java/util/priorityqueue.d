/*
 * Copyright (c) 2003, 2019, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

// Ported from openjdk 21.0.13, src/java.base/share/classes/java/util/PriorityQueue.java
// Modified by the Flint authors.
module flint.java.util.priorityqueue;

import flint.java.lang : IllegalArgumentException, IllegalStateException, NullPointerException, javaEquals;
import flint.java.util : AbstractCollection, Collection, Comparator,
    ConcurrentModificationException, Iterator, NoSuchElementException, Objects, compareNatural;
import flint.java.util.queue : Queue;

@safe:

/++
Java's `PriorityQueue`: an unbounded priority queue backed by a binary heap.

The head is the least element under the queue's ordering, which is either the comparator given at construction or the
elements' natural ordering. Ties are broken arbitrarily. The storage is a complete binary heap in an array: the children
of `slots[n]` are `slots[2*n+1]` and `slots[2*(n+1)]`, and `count` marks the live prefix, so a primitive element type
keeps its real `T.init` values.

Java's elements are references and null is prohibited, so `offer`/`add` and the collection constructor throw
`NullPointerException` for a null reference element; for a primitive or struct `T` there is no null to reject. The
iterator traverses the heap array in no particular order and supports `remove`. `Spliterator`, serialization and the
`SortedSet` constructor are deferred; the `PriorityQueue` copy constructor, and the `Collection` constructor when the
argument is actually a `PriorityQueue`, keep the source's comparator.

Unlike Java, this port extends `AbstractCollection` and `Queue` directly rather than `AbstractQueue`, which is not
ported. `AbstractQueue` only supplies defaults that this class overrides, so the observable contract is unchanged.
+/
class PriorityQueue(T) : AbstractCollection!T, Queue!T
{
    private T[] slots;
    private int count;
    private Comparator!T ordering;
    private int modCount;

    private enum int defaultInitialCapacity = 11;

    /// An empty queue with Java's initial capacity, ordered naturally.
    this()
    {
        this(defaultInitialCapacity, null);
    }

    /// An empty queue with room for `initialCapacity` elements, ordered naturally.
    this(int initialCapacity)
    {
        this(initialCapacity, null);
    }

    /// An empty queue with Java's initial capacity, ordered by `comparator` (`null` for natural order).
    this(Comparator!T comparator)
    {
        this(defaultInitialCapacity, comparator);
    }

    /// An empty queue with room for `initialCapacity` elements, ordered by `comparator`.
    this(int initialCapacity, Comparator!T comparator)
    {
        if (initialCapacity < 1)
            throw new IllegalArgumentException();
        slots = new T[](cast(size_t) initialCapacity);
        ordering = comparator;
    }

    /// A queue of `c`'s elements, ordered naturally unless `c` is a `PriorityQueue`, whose ordering is then kept.
    this(Collection!T c)
    {
        if (c is null)
            throw new NullPointerException();
        if (auto source = cast(PriorityQueue!T) c)
        {
            ordering = source.ordering;
            count = source.count;
            slots = source.slots.dup;
            return;
        }
        auto elements = c.toArray();
        slots = new T[](elements.length < 1 ? 1 : elements.length);
        foreach (e; elements)
        {
            if (Objects.isNull(e))
                throw new NullPointerException();
            slots[count++] = e;
        }
        heapify();
    }

    /// A queue with `c`'s elements and the same ordering as `c`.
    this(PriorityQueue!T c)
    {
        if (c is null)
            throw new NullPointerException();
        ordering = c.ordering;
        count = c.count;
        slots = c.slots.dup;
    }

    /// Java's `add`: `offer`.
    override bool add(T e)
    {
        return offer(e);
    }

    /// Java's `offer`: insert `e`.
    bool offer(T e)
    {
        if (Objects.isNull(e))
            throw new NullPointerException();
        modCount++;
        const int i = count;
        if (i >= capacity)
            grow(i + 1);
        siftUp(i, e);
        count = i + 1;
        return true;
    }

    /// Java's `peek`: the head, or `T.init` when empty.
    T peek()
    {
        return count == 0 ? T.init : slots[0];
    }

    /// Java's `element`: the head, throwing `NoSuchElementException` when empty.
    T element()
    {
        if (count == 0)
            throw new NoSuchElementException();
        return slots[0];
    }

    /// Java's `poll`: remove and return the head, or `T.init` when empty.
    T poll()
    {
        if (count == 0)
            return T.init;
        modCount++;
        const T result = slots[0];
        const int n = --count;
        const T x = slots[n];
        slots[n] = T.init;
        if (n > 0)
            siftDown(0, x);
        return result;
    }

    /// Java's `remove()`: `poll`, throwing `NoSuchElementException` when empty.
    T remove()
    {
        if (count == 0)
            throw new NoSuchElementException();
        return poll();
    }

    /// Java's `remove(Object)`: remove one element equal to `o`.
    override bool remove(T o)
    {
        const int i = indexOf(o);
        if (i == -1)
            return false;
        T moved;
        removeAt(i, moved);
        return true;
    }

    /// Java's `contains`: whether an element equals `o`.
    override bool contains(T o)
    {
        return indexOf(o) >= 0;
    }

    /// Java's `size`.
    override int size() pure nothrow @nogc
    {
        return count;
    }

    /// Java's `isEmpty`.
    override bool isEmpty() pure nothrow @nogc
    {
        return count == 0;
    }

    /// Java's `iterator`: the heap array in no particular order, fail-fast, with `remove`.
    override Iterator!T iterator()
    {
        return new PriorityQueueCursor!T(this);
    }

    /// Java's `toArray`, in heap order.
    override T[] toArray()
    {
        auto result = new T[](cast(size_t) count);
        foreach (k; 0 .. count)
            result[k] = slots[k];
        return result;
    }

    /// Java's `clear`.
    override void clear()
    {
        modCount++;
        foreach (ref e; slots[0 .. count])
            e = T.init;
        count = 0;
    }

    /// Java's `comparator`, or null for the natural ordering.
    Comparator!T comparator()
    {
        return ordering;
    }

    /// Java's inherited `Object.equals`: identity, as `PriorityQueue` does not override equality.
    bool equals(Object o)
    {
        return o is this;
    }

    /// Java's inherited `Object.hashCode`: identity, as `PriorityQueue` does not override equality.
    int hashCode()
    {
        return cast(int)(cast(size_t) cast(const(void)*) this);
    }

    /// The current array length.
    private int capacity() const pure nothrow @nogc
    {
        return cast(int) slots.length;
    }

    /// The index of an element equal to `o`, or -1.
    private int indexOf(T o) const
    {
        if (Objects.isNull(o))
            return -1;
        foreach (i; 0 .. count)
            if (javaEquals(slots[i], o))
                return i;
        return -1;
    }

    /// Remove one element identical to `o`; used by the iterator for elements it has already visited.
    private void removeEq(T o)
    {
        foreach (i; 0 .. count)
            if (sameElement(o, slots[i]))
            {
                T moved;
                removeAt(i, moved);
                break;
            }
    }

    /// Remove the element at index `i`; report the element that moved into the already-visited region, if any.
    private bool removeAt(int i, out T moved)
    {
        modCount++;
        const int s = --count;
        moved = T.init;
        const T last = slots[s];
        slots[s] = T.init;
        if (s == i)
            return false;
        int k = siftDown(i, last);
        if (k == i)
        {
            k = siftUp(i, last);
            if (k != i)
            {
                moved = last;
                return true;
            }
        }
        return false;
    }

    /// Insert `x` at `k`, promoting it until its parent orders before it; return its final index.
    private int siftUp(int k, T x)
    {
        return ordering is null ? siftUpComparable(k, x) : siftUpUsingComparator(k, x);
    }

    private int siftUpComparable(int k, T x)
    {
        while (k > 0)
        {
            const int parent = (k - 1) >>> 1;
            const T e = slots[parent];
            if (compareNatural!T(x, e) >= 0)
                break;
            slots[k] = e;
            k = parent;
        }
        slots[k] = x;
        return k;
    }

    private int siftUpUsingComparator(int k, T x)
    {
        while (k > 0)
        {
            const int parent = (k - 1) >>> 1;
            const T e = slots[parent];
            if (ordering.compare(x, e) >= 0)
                break;
            slots[k] = e;
            k = parent;
        }
        slots[k] = x;
        return k;
    }

    /// Insert `x` at `k`, demoting it until its children order after it; return its final index.
    private int siftDown(int k, T x)
    {
        return ordering is null ? siftDownComparable(k, x, count) : siftDownUsingComparator(k, x, count);
    }

    private int siftDownComparable(int k, T x, int n)
    {
        const int half = n >>> 1;
        while (k < half)
        {
            int child = (k << 1) + 1;
            T c = slots[child];
            const int right = child + 1;
            if (right < n && compareNatural!T(c, slots[right]) > 0)
                c = slots[child = right];
            if (compareNatural!T(x, c) <= 0)
                break;
            slots[k] = c;
            k = child;
        }
        slots[k] = x;
        return k;
    }

    private int siftDownUsingComparator(int k, T x, int n)
    {
        const int half = n >>> 1;
        while (k < half)
        {
            int child = (k << 1) + 1;
            T c = slots[child];
            const int right = child + 1;
            if (right < n && ordering.compare(c, slots[right]) > 0)
                c = slots[child = right];
            if (ordering.compare(x, c) <= 0)
                break;
            slots[k] = c;
            k = child;
        }
        slots[k] = x;
        return k;
    }

    /// Establish the heap invariant over the whole live array in linear time (Floyd, 1964).
    private void heapify()
    {
        const int n = count;
        for (int i = (n >>> 1) - 1; i >= 0; i--)
        {
            const T x = slots[i];
            if (ordering is null)
                siftDownComparable(i, x, n);
            else
                siftDownUsingComparator(i, x, n);
        }
    }

    /// Grow the array to hold at least `minCapacity` elements.
    private void grow(int minCapacity)
    {
        const int oldCapacity = capacity;
        int newCapacity = oldCapacity < 64 ? oldCapacity * 2 + 2 : oldCapacity + (oldCapacity >> 1);
        if (newCapacity < minCapacity)
            newCapacity = minCapacity;
        auto grown = new T[](cast(size_t) newCapacity);
        foreach (k; 0 .. count)
            grown[k] = slots[k];
        slots = grown;
    }

    /// Whether `a` and `b` are the same element: identity for references, value for primitives.
    private static bool sameElement(T a, T b)
    {
        static if (is(T == class) || is(T == interface) || is(T == U[], U) || is(T == U*, U))
            return a is b;
        else
            return a == b;
    }
}

/// Java's fail-fast `Iterator` over a `PriorityQueue` in heap order.
private final class PriorityQueueCursor(T) : Iterator!T
{
    private PriorityQueue!T queue;
    private int cursor;
    private int lastRet = -1;
    private T[] forgetMeNot;
    private int forgetHead;
    private T lastRetElt;
    private bool hasLastRetElt;
    private int expectedModCount;

    private this(PriorityQueue!T queue)
    {
        this.queue = queue;
        expectedModCount = queue.modCount;
    }

    bool hasNext() pure nothrow @nogc
    {
        return cursor < queue.count || forgetHead < forgetMeNot.length;
    }

    T next()
    {
        if (expectedModCount != queue.modCount)
            throw new ConcurrentModificationException();
        if (cursor < queue.count)
        {
            lastRet = cursor;
            hasLastRetElt = false;
            return queue.slots[cursor++];
        }
        if (forgetHead < forgetMeNot.length)
        {
            lastRet = -1;
            lastRetElt = forgetMeNot[forgetHead++];
            hasLastRetElt = true;
            return lastRetElt;
        }
        throw new NoSuchElementException();
    }

    void remove()
    {
        if (expectedModCount != queue.modCount)
            throw new ConcurrentModificationException();
        if (lastRet != -1)
        {
            T moved;
            const bool movedOut = queue.removeAt(lastRet, moved);
            lastRet = -1;
            if (!movedOut)
                cursor--;
            else
                forgetMeNot ~= moved;
        }
        else if (hasLastRetElt)
        {
            queue.removeEq(lastRetElt);
            hasLastRetElt = false;
        }
        else
        {
            throw new IllegalStateException();
        }
        expectedModCount = queue.modCount;
    }
}
