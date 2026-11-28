// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/concurrent/CopyOnWriteArrayList.java
/*
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

/*
 * This file is available under and governed by the GNU General Public
 * License version 2 only, as published by the Free Software Foundation.
 * However, the following notice accompanied the original version of this
 * file:
 *
 * Written by Doug Lea with assistance from members of JCP JSR-166
 * Expert Group and released to the public domain, as explained at
 * http://creativecommons.org/publicdomain/zero/1.0/
 */

// Modified by the Flint authors: reads load one published immutable snapshot; writes copy the whole array
// under a mutex and publish the new snapshot. Java's volatile array field is one `ProcessSlot`; the iterator
// is a snapshot over the array it was created from. The generics are D templates; the erased engine that
// keeps class-element lists on one instantiation is deferred to the B-1 follow-up.
module flint.java.util.concurrent.copyonwritearraylist;

import core.sync.mutex : Mutex;
import flint.conc.slot : ProcessSlot;
import flint.java.lang : IndexOutOfBoundsException, UnsupportedOperationException, javaEquals, javaHashCode, valueOf;
import flint.java.util : AbstractList, Collection, Comparator, Iterator, List,
    NoSuchElementException, compareNatural, stableSort;

@safe:

/// The immutable array view a reader sees. The list publishes a new one on every write and never mutates it.
private final class CopyOnWriteSnapshot(T)
{
    T[] items;

    this(T[] items) pure nothrow @nogc
    {
        this.items = items;
    }
}

/// A snapshot iterator: `next` reads the array captured at construction; `remove` is unsupported, as in Java.
private final class CopyOnWriteIterator(T) : Iterator!T
{
    private T[] items;
    private size_t cursor;

    this(T[] items) pure nothrow @nogc
    {
        this.items = items;
    }

    bool hasNext() pure nothrow @nogc
    {
        return cursor < items.length;
    }

    T next()
    {
        if (cursor >= items.length)
            throw new NoSuchElementException;
        return items[cursor++];
    }

    void remove()
    {
        throw new UnsupportedOperationException;
    }
}

/++
A thread-safe `List` whose writes copy the backing array. Reads never lock; each read sees the array published
when it started. An iterator is a snapshot: later writes do not appear in it. Null elements are allowed.

The storage is one immutable `T[]` behind a `ProcessSlot`; a write takes the mutex, copies the array, and
publishes the copy. This is Java's copy-on-write list with the volatile array field replaced by the process slot.
+/
class CopyOnWriteArrayList(T) : AbstractList!T
{
    /// Descriptor hook: the storage is private, not JSON fields.
    enum __flintOpaque = true;

    private shared ProcessSlot!(CopyOnWriteSnapshot!T) slot;
    private Mutex lock;

    /// An empty list.
    this()
    {
        slot.set(new CopyOnWriteSnapshot!T(null));
        lock = new Mutex;
    }

    /// A list holding a copy of `elements`.
    this(T[] elements)
    {
        slot.set(new CopyOnWriteSnapshot!T(elements.dup));
        lock = new Mutex;
    }

    /// A list holding the elements of `elements`, in its iteration order.
    this(Collection!T elements)
    {
        this(elements.toArray());
    }

    /// The array a reader sees now. The returned array is never mutated by the list.
    private CopyOnWriteSnapshot!T current() nothrow @nogc
    {
        return slot.get();
    }

    private void publish(T[] items)
    {
        slot.set(new CopyOnWriteSnapshot!T(items));
    }

    override int size() nothrow @nogc
    {
        return cast(int) current().items.length;
    }

    override T get(int index)
    {
        auto items = current().items;
        checkIndex(index, items.length);
        return items[index];
    }

    override T set(int index, T element)
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        auto items = current().items;
        checkIndex(index, items.length);
        auto previous = items[index];
        auto copy = items.dup;
        copy[index] = element;
        publish(copy);
        return previous;
    }

    override void add(int index, T element)
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        auto items = current().items;
        if (index < 0 || index > items.length)
            throw new IndexOutOfBoundsException("Index: " ~ valueOf(index) ~ ", Size: " ~ valueOf(cast(int) items
                    .length));
        auto copy = new T[items.length + 1];
        copy[0 .. index] = items[0 .. index];
        copy[index] = element;
        copy[index + 1 .. $] = items[index .. $];
        publish(copy);
    }

    override bool add(T element)
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        auto items = current().items;
        auto copy = new T[items.length + 1];
        copy[0 .. items.length] = items;
        copy[items.length] = element;
        publish(copy);
        return true;
    }

    override T removeAt(int index)
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        auto items = current().items;
        checkIndex(index, items.length);
        auto removed = items[index];
        const remaining = cast(size_t) cast(ptrdiff_t) items.length - 1;
        auto copy = new T[remaining];
        copy[0 .. index] = items[0 .. index];
        copy[index .. $] = items[index + 1 .. $];
        publish(copy);
        return removed;
    }

    override bool remove(T element)
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        auto items = current().items;
        foreach (i, e; items)
            if (javaEquals(e, element))
            {
                const remaining = cast(size_t) cast(ptrdiff_t) items.length - 1;
                auto copy = new T[remaining];
                copy[0 .. i] = items[0 .. i];
                copy[i .. $] = items[i + 1 .. $];
                publish(copy);
                return true;
            }
        return false;
    }

    override bool removeIf(bool delegate(T) @safe filter)
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        auto items = current().items;
        auto kept = new T[items.length];
        size_t count;
        foreach (e; items)
            if (!filter(e))
                kept[count++] = e;
        if (count == items.length)
            return false;
        publish(kept[0 .. count]);
        return true;
    }

    override void clear()
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        publish(null);
    }

    override T[] toArray()
    {
        return current().items.dup;
    }

    override Iterator!T iterator()
    {
        return new CopyOnWriteIterator!T(current().items);
    }

    override bool contains(T element)
    {
        foreach (e; current().items)
            if (javaEquals(e, element))
                return true;
        return false;
    }

    override int indexOf(T element)
    {
        auto items = current().items;
        foreach (i, e; items)
            if (javaEquals(e, element))
                return cast(int) i;
        return -1;
    }

    override int lastIndexOf(T element)
    {
        auto items = current().items;
        for (int i = cast(int) items.length - 1; i >= 0; i--)
            if (javaEquals(items[i], element))
                return i;
        return -1;
    }

    override void sort(Comparator!T comparator)
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        auto copy = current().items.dup;
        if (comparator is null)
            stableSort(copy, (T a, T b) => compareNatural(a, b));
        else
            stableSort(copy, &comparator.compare);
        publish(copy);
    }

    override bool equals(Object other)
    {
        auto list = cast(List!T) other;
        if (list is null)
            return false;
        auto items = current().items;
        if (cast(int) items.length != list.size())
            return false;
        foreach (i, e; items)
            if (!javaEquals(e, list.get(cast(int) i)))
                return false;
        return true;
    }

    override size_t toHash() @safe nothrow
    {
        try
        {
            size_t hash = 1;
            foreach (e; current().items)
                hash = hash * 31 + javaHashCode(e);
            return hash;
        }
        catch (Exception)
            return 0;
    }

    override bool opEquals(Object other)
    {
        return equals(other);
    }
}

private void checkIndex(int index, size_t length)
{
    if (index < 0 || index >= length)
        throw new IndexOutOfBoundsException("Index: " ~ valueOf(index) ~ ", Size: " ~ valueOf(cast(int) length));
}
