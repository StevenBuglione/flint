/*
 * Copyright (c) 1997, 2022, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13, src/java.base/share/classes/java/util/ArrayDeque.java
// Modified by the Flint authors.
module flint.java.util.arraydeque;

import flint.java.lang : IllegalStateException, NullPointerException, javaEquals;
import flint.java.util : AbstractCollection, Collection, ConcurrentModificationException, Iterator,
    NoSuchElementException, Objects;
import flint.java.util.deque : Deque;

@safe:

/// Whether an element of `T` can be null: Java's reference element types carry the prohibition on null elements.
private enum bool isNullable(T) = is(T == class) || is(T == interface) || is(T == U[], U) || is(T
            : const(char)[]) || is(T == U*, U);

/++
Java's `ArrayDeque`: a resizable circular array that implements `Deque`, usable as a queue or a stack.

The storage is a ring buffer with one always-empty slot at `tail`, so an empty deque is `head == tail` and the size is
the circular distance between them. `addFirst`/`addLast` write the new element and then grow when the write filled the
last empty slot, which keeps the empty/full disambiguation unnecessary. The elements array always points at the live
buffer; a removed slot is reset to `T.init` so a removed reference can be collected.

Java's elements are references and null is prohibited, so `addFirst`/`addLast`/`offer*`/`push`/`add` throw
`NullPointerException` for a null reference element; for a primitive or struct `T` there is no null to reject. As in
Java, this class uses identity `equals`/`hashCode` (it does not override them). `Cloneable`'s `clone` is ported,
serialization and `Spliterator` are deferred.
+/
class ArrayDeque(T) : AbstractCollection!T, Deque!T
{
    private T[] elements;
    private int head;
    private int tail;

    /// An empty deque whose array holds 16 elements, matching Java's initial capacity.
    this()
    {
        elements = new T[](17);
    }

    /// An empty deque with room for at least `numElements` elements.
    this(int numElements)
    {
        elements = new T[](numElements < 1 ? 1 : cast(size_t) numElements + 1);
    }

    /// A deque of `c`'s elements, in its iteration order.
    this(Collection!T c)
    {
        if (c is null)
            throw new NullPointerException();
        const int count = c.size();
        elements = new T[](count < 1 ? 1 : cast(size_t) count + 1);
        addAll(c);
    }

    /// Java's `addFirst`: insert `e` at the front.
    void addFirst(T e)
    {
        checkElement(e);
        if (dec(head, capacity) == tail)
            grow(1);
        head = dec(head, capacity);
        elements[head] = e;
    }

    /// Java's `addLast`: insert `e` at the tail.
    void addLast(T e)
    {
        checkElement(e);
        if (inc(tail, capacity) == head)
            grow(1);
        elements[tail] = e;
        tail = inc(tail, capacity);
    }

    /// Java's `addAll`: append every element of `c` at the tail.
    override bool addAll(Collection!T c)
    {
        if (c is null)
            throw new NullPointerException();
        const int before = size();
        foreach (e; c.toArray())
            addLast(e);
        return size() > before;
    }

    /// Java's `offerFirst`.
    bool offerFirst(T e)
    {
        addFirst(e);
        return true;
    }

    /// Java's `offerLast`.
    bool offerLast(T e)
    {
        addLast(e);
        return true;
    }

    /// Java's `removeFirst`, throwing `NoSuchElementException` when empty.
    T removeFirst()
    {
        if (head == tail)
            throw new NoSuchElementException();
        return pollFirst();
    }

    /// Java's `removeLast`, throwing `NoSuchElementException` when empty.
    T removeLast()
    {
        if (head == tail)
            throw new NoSuchElementException();
        return pollLast();
    }

    /// Java's `pollFirst`, or `T.init` when empty.
    T pollFirst() pure nothrow @nogc
    {
        if (head == tail)
            return T.init;
        auto result = elements[head];
        elements[head] = T.init;
        head = inc(head, capacity);
        return result;
    }

    /// Java's `pollLast`, or `T.init` when empty.
    T pollLast() pure nothrow @nogc
    {
        if (head == tail)
            return T.init;
        tail = dec(tail, capacity);
        auto result = elements[tail];
        elements[tail] = T.init;
        return result;
    }

    /// Java's `getFirst`, throwing `NoSuchElementException` when empty.
    T getFirst()
    {
        if (head == tail)
            throw new NoSuchElementException();
        return elements[head];
    }

    /// Java's `getLast`, throwing `NoSuchElementException` when empty.
    T getLast()
    {
        if (head == tail)
            throw new NoSuchElementException();
        return elements[dec(tail, capacity)];
    }

    /// Java's `peekFirst`, or `T.init` when empty.
    T peekFirst() pure nothrow @nogc
    {
        return head == tail ? T.init : elements[head];
    }

    /// Java's `peekLast`, or `T.init` when empty.
    T peekLast() pure nothrow @nogc
    {
        return head == tail ? T.init : elements[dec(tail, capacity)];
    }

    /// Java's `removeFirstOccurrence`: remove the first element equal to `o`.
    bool removeFirstOccurrence(T o)
    {
        if (Objects.isNull(o))
            return false;
        const int count = size();
        const int cap = capacity;
        int index = head;
        for (int k = 0; k < count; k++)
        {
            if (javaEquals(elements[index], o))
            {
                deleteAt(index);
                return true;
            }
            index = inc(index, cap);
        }
        return false;
    }

    /// Java's `removeLastOccurrence`: remove the last element equal to `o`.
    bool removeLastOccurrence(T o)
    {
        if (Objects.isNull(o))
            return false;
        const int count = size();
        const int cap = capacity;
        int index = dec(tail, cap);
        for (int k = count; k > 0; k--)
        {
            if (javaEquals(elements[index], o))
            {
                deleteAt(index);
                return true;
            }
            index = dec(index, cap);
        }
        return false;
    }

    /// Java's `add`: `addLast`.
    override bool add(T e)
    {
        addLast(e);
        return true;
    }

    /// Java's `offer`: `offerLast`.
    bool offer(T e)
    {
        return offerLast(e);
    }

    /// Java's `remove()`: `removeFirst`.
    T remove()
    {
        return removeFirst();
    }

    /// Java's `poll`: `pollFirst`.
    T poll()
    {
        return pollFirst();
    }

    /// Java's `element`: `getFirst`.
    T element()
    {
        return getFirst();
    }

    /// Java's `peek`: `peekFirst`.
    T peek()
    {
        return peekFirst();
    }

    /// Java's `push`: `addFirst`.
    void push(T e)
    {
        addFirst(e);
    }

    /// Java's `pop`: `removeFirst`.
    T pop()
    {
        return removeFirst();
    }

    /// Java's `size`.
    override int size() pure nothrow @nogc
    {
        return sub(tail, head, capacity);
    }

    /// Java's `isEmpty`.
    override bool isEmpty() pure nothrow @nogc
    {
        return head == tail;
    }

    /// Java's `iterator`: first to last.
    override Iterator!T iterator()
    {
        return new ArrayDequeCursor!T(this, false);
    }

    /// Java's `descendingIterator`: last to first.
    Iterator!T descendingIterator()
    {
        return new ArrayDequeCursor!T(this, true);
    }

    /// Java's `removeIf`: remove every element matching `filter`.
    override bool removeIf(bool delegate(T) @safe filter)
    {
        if (filter is null)
            throw new NullPointerException();
        return super.removeIf(filter);
    }

    /// Java's `removeAll`: remove every element contained in `c`.
    override bool removeAll(Collection!T c)
    {
        if (c is null)
            throw new NullPointerException();
        return super.removeAll(c);
    }

    /// Java's `retainAll`: keep only the elements contained in `c`.
    override bool retainAll(Collection!T c)
    {
        if (c is null)
            throw new NullPointerException();
        return super.retainAll(c);
    }

    /// Java's `clear`.
    override void clear()
    {
        foreach (ref e; elements)
            e = T.init;
        head = tail = 0;
    }

    /// Java's `toArray`, in first-to-last order.
    override T[] toArray()
    {
        const int count = size();
        auto result = new T[](cast(size_t) count);
        foreach (k; 0 .. count)
            result[k] = elements[at(k)];
        return result;
    }

    /// Java's `clone`: a shallow copy with independent storage.
    ArrayDeque!T clone()
    {
        auto result = new ArrayDeque!T();
        result.elements = elements.dup;
        result.head = head;
        result.tail = tail;
        return result;
    }

    /// Java's inherited `Object.equals`: identity, as `ArrayDeque` does not override equality.
    bool equals(Object o)
    {
        return o is this;
    }

    /// Java's inherited `Object.hashCode`: identity, as `ArrayDeque` does not override equality.
    int hashCode()
    {
        return cast(int)(cast(size_t) cast(const(void)*) this);
    }

    /// Bring `Collection`'s `remove(T)` into the same overload set as `remove()`.
    alias remove = AbstractCollection!T.remove;

    /// The physical array index of logical index `index`.
    private int at(int index) const pure nothrow @nogc
    {
        const int shifted = head + index;
        const int cap = capacity;
        return shifted < cap ? shifted : shifted - cap;
    }

    /// The current array length.
    private int capacity() const pure nothrow @nogc
    {
        return cast(int) elements.length;
    }

    /// Circularly increments `i` modulo `modulus`.
    private static int inc(int i, int modulus) pure nothrow @nogc
    {
        return ++i >= modulus ? 0 : i;
    }

    /// Circularly decrements `i` modulo `modulus`.
    private static int dec(int i, int modulus) pure nothrow @nogc
    {
        return --i < 0 ? modulus - 1 : i;
    }

    /// The circular distance from `j` to `i`, zero when equal.
    private static int sub(int i, int j, int modulus) pure nothrow @nogc
    {
        i -= j;
        return i < 0 ? i + modulus : i;
    }

    /// Reject a null reference element, as Java's `ArrayDeque` does.
    private static void checkElement(T e)
    {
        if (Objects.isNull(e))
            throw new NullPointerException();
    }

    /// Add room for `needed` more elements, laying the live elements out linearly from index zero.
    private void grow(int needed)
    {
        const int count = size();
        int newCapacity = capacity * 2;
        if (newCapacity < count + needed + 1)
            newCapacity = count + needed + 1;
        auto grown = new T[](cast(size_t) newCapacity);
        foreach (k; 0 .. count)
            grown[k] = elements[at(k)];
        elements = grown;
        head = 0;
        tail = count;
    }

    /// Remove the element at physical index `i`; return whether the elements after it moved backwards.
    private bool deleteAt(int i)
    {
        const int cap = capacity;
        const int count = size();
        const int front = sub(i, head, cap);
        const int back = sub(tail, i, cap) - 1;
        if (front < back)
        {
            for (int k = front; k > 0; k--)
                elements[at(k)] = elements[at(k - 1)];
            elements[head] = T.init;
            head = inc(head, cap);
            return false;
        }

        for (int k = front; k < count - 1; k++)
            elements[at(k)] = elements[at(k + 1)];
        tail = dec(tail, cap);
        elements[tail] = T.init;
        return true;
    }
}

/// Java's fail-fast `Iterator` over an `ArrayDeque`, in either direction.
private final class ArrayDequeCursor(T) : Iterator!T
{
    private ArrayDeque!T deque;
    private int remaining;
    private int cursor;
    private int lastRet = -1;
    private bool descending;

    private this(ArrayDeque!T deque, bool descending)
    {
        this.deque = deque;
        this.descending = descending;
        remaining = deque.size();
        cursor = descending ? ArrayDeque!T.dec(deque.tail, deque.capacity) : deque.head;
    }

    bool hasNext() pure nothrow @nogc
    {
        return remaining > 0;
    }

    T next()
    {
        if (remaining <= 0)
            throw new NoSuchElementException();
        static if (isNullable!T)
        {
            if (deque.elements[cursor] is null)
                throw new ConcurrentModificationException();
        }
        auto result = deque.elements[cursor];
        lastRet = cursor;
        cursor = descending ? ArrayDeque!T.dec(cursor, deque.capacity) : ArrayDeque!T.inc(cursor, deque.capacity);
        remaining--;
        return result;
    }

    void remove()
    {
        if (lastRet < 0)
            throw new IllegalStateException();
        const bool leftShifted = deque.deleteAt(lastRet);
        if (descending != leftShifted)
            cursor = descending ? ArrayDeque!T.inc(cursor, deque.capacity) : ArrayDeque!T.dec(cursor, deque.capacity);
        lastRet = -1;
    }
}
