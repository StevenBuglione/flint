// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/concurrent/CopyOnWriteArraySet.java
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

// Modified by the Flint authors: reads load one published immutable snapshot; writes take the mutex, copy the
// array and publish the new snapshot. Java's volatile array field is one `ProcessSlot`; the iterator is a
// snapshot over the array it was created from. The generics are D templates.
module flint.java.util.concurrent.copyonwritearrayset;

import core.sync.mutex : Mutex;
import flint.conc.slot : ProcessSlot;
import flint.java.lang : UnsupportedOperationException, javaEquals, javaHashCode, valueOf;
import flint.java.util : AbstractCollection, Collection, Iterator, NoSuchElementException, Set;

@safe:

/// The immutable array view a reader sees. The set publishes a new one on every write and never mutates it.
private final class SetSnapshot(T)
{
    T[] items;

    this(T[] items) pure nothrow @nogc
    {
        this.items = items;
    }
}

/// A snapshot iterator: `next` reads the array captured at construction; `remove` is unsupported, as in Java.
private final class SetIterator(T) : Iterator!T
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
A thread-safe `Set` backed by a copy-on-write array. Reads never lock and see the snapshot published when they
started; writes take the mutex, copy the whole array, and publish the copy. Iteration is over a snapshot, so a
caller never sees a concurrent write. Duplicate elements are rejected by `add` and `addAll`, as in Java. Null
elements are allowed.
+/
class CopyOnWriteArraySet(T) : AbstractCollection!T, Set!T
{
    /// Descriptor hook: the storage is private, not JSON fields.
    enum __flintOpaque = true;

    private shared ProcessSlot!(SetSnapshot!T) slot;
    private Mutex lock;

    /// An empty set.
    this()
    {
        slot.set(new SetSnapshot!T(null));
        lock = new Mutex;
    }

    /// A set holding the distinct elements of `c`, in its iteration order.
    this(Collection!T c)
    {
        slot.set(new SetSnapshot!T(null));
        lock = new Mutex;
        addAll(c);
    }

    /// The array a reader sees now. The returned array is never mutated by the set.
    private SetSnapshot!T current() nothrow @nogc
    {
        return slot.get();
    }

    private void publish(T[] items)
    {
        slot.set(new SetSnapshot!T(items));
    }

    private static bool containsIn(T[] items, T element)
    {
        foreach (e; items)
            if (javaEquals(e, element))
                return true;
        return false;
    }

    override int size() nothrow @nogc
    {
        return cast(int) current().items.length;
    }

    override bool isEmpty() nothrow @nogc
    {
        return current().items.length == 0;
    }

    override bool contains(T element)
    {
        return containsIn(current().items, element);
    }

    override bool containsAll(Collection!T c)
    {
        foreach (e; c.toArray())
            if (!containsIn(current().items, e))
                return false;
        return true;
    }

    override T[] toArray()
    {
        return current().items.dup;
    }

    override Iterator!T iterator()
    {
        return new SetIterator!T(current().items);
    }

    override bool add(T element)
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        auto items = current().items;
        if (containsIn(items, element))
            return false;
        auto copy = new T[items.length + 1];
        copy[0 .. items.length] = items;
        copy[items.length] = element;
        publish(copy);
        return true;
    }

    override bool addAll(Collection!T c)
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        auto working = current().items;
        bool changed;
        foreach (candidate; c.toArray())
        {
            if (containsIn(working, candidate))
                continue;
            auto copy = new T[working.length + 1];
            copy[0 .. working.length] = working;
            copy[working.length] = candidate;
            working = copy;
            changed = true;
        }
        if (changed)
            publish(working);
        return changed;
    }

    override bool remove(T element)
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        auto items = current().items;
        foreach (i, e; items)
        {
            if (!javaEquals(e, element))
                continue;
            const remaining = cast(size_t) cast(ptrdiff_t) items.length - 1;
            auto copy = new T[remaining];
            copy[0 .. i] = items[0 .. i];
            copy[i .. $] = items[i + 1 .. $];
            publish(copy);
            return true;
        }
        return false;
    }

    override void clear()
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        publish(null);
    }

    override bool removeIf(bool delegate(T) @safe filter)
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();
        auto items = current().items;
        T[] kept;
        kept.reserve(items.length);
        foreach (e; items)
            if (!filter(e))
                kept ~= e;
        if (kept.length == items.length)
            return false;
        publish(kept);
        return true;
    }

    override bool removeAll(Collection!T c)
    {
        return removeIf((T e) => c.contains(e));
    }

    override bool retainAll(Collection!T c)
    {
        return removeIf((T e) => !c.contains(e));
    }

    override bool isSet()
    {
        return true;
    }

    /// Java's `Set.equals`: another set with the same elements.
    override bool equals(Object other)
    {
        if (other is this)
            return true;
        auto set = cast(Set!T) other;
        if (set is null)
            return false;
        auto elements = current().items;
        if (cast(int) elements.length != set.size())
            return false;
        foreach (e; elements)
            if (!set.contains(e))
                return false;
        return true;
    }

    /// Java's `Set.hashCode`: the sum of the elements' hash codes.
    override int hashCode()
    {
        int hash;
        foreach (e; current().items)
            hash += javaHashCode(e);
        return hash;
    }

    override bool opEquals(Object other)
    {
        return equals(other);
    }

    override size_t toHash() @safe nothrow
    {
        try
            return cast(uint) hashCode();
        catch (Exception)
            return 0;
    }
}
