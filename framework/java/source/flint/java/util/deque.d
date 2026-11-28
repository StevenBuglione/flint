/*
 * Copyright (c) 2003, 2022, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13, src/java.base/share/classes/java/util/Deque.java
// Modified by the Flint authors.
module flint.java.util.deque;

import flint.engine.aot.any : Any;
import flint.java.lang : javaEquals, valueOf;
import flint.java.util : Collection, Iterator;
import flint.java.util.queue : Queue;

@safe:

/// Java's `Deque`: a double-ended queue, also usable as a stack.
///
/// Java 21's `Deque` extends `SequencedCollection`. That hierarchy is deferred with the collection redesign, so this
/// interface extends `Queue` only and declares `reversed()` itself. `poll*` and `peek*` return `T.init` when empty, as
/// `Queue` does. The reversed view is a live view, as Java's is.
interface Deque(T) : Queue!T
{
    /// Java's `addFirst`.
    void addFirst(T e);
    /// Java's `addLast`.
    void addLast(T e);
    /// Java's `offerFirst`.
    bool offerFirst(T e);
    /// Java's `offerLast`.
    bool offerLast(T e);
    /// Java's `removeFirst`, throwing `NoSuchElementException` when empty.
    T removeFirst();
    /// Java's `removeLast`, throwing `NoSuchElementException` when empty.
    T removeLast();
    /// Java's `pollFirst`, or `T.init` when empty.
    T pollFirst();
    /// Java's `pollLast`, or `T.init` when empty.
    T pollLast();
    /// Java's `getFirst`, throwing `NoSuchElementException` when empty.
    T getFirst();
    /// Java's `getLast`, throwing `NoSuchElementException` when empty.
    T getLast();
    /// Java's `peekFirst`, or `T.init` when empty.
    T peekFirst();
    /// Java's `peekLast`, or `T.init` when empty.
    T peekLast();
    /// Java's `removeFirstOccurrence`.
    bool removeFirstOccurrence(T o);
    /// Java's `removeLastOccurrence`.
    bool removeLastOccurrence(T o);
    /// Java's `push`: `addFirst`.
    void push(T e);
    /// Java's `pop`: `removeFirst`.
    T pop();
    /// Java's `descendingIterator`.
    Iterator!T descendingIterator();

    /// Java's `reversed`: a live view of this deque in reverse order. Reversing the view returns this deque.
    final Deque!T reversed()
    {
        if (auto view = cast(ReversedDeque!T) this)
            return view.original;
        return new ReversedDeque!T(this);
    }
}

/// The storage-free `Collection` half of the reversed view, in terms of `iterator`, `size` and `add`.
private abstract class DequeViewBase(T) : Deque!T
{
    override string toString()
    {
        string result = "[";
        bool first = true;
        for (auto it = iterator(); it.hasNext();)
        {
            auto e = it.next();
            if (!first)
                result ~= ", ";
            first = false;
            static if (is(T == class) || is(T == interface))
                result ~= (cast(Object) e) is this ? "(this Collection)" : valueOf(e);
            else
                result ~= valueOf(e);
        }
        return result ~ "]";
    }

    bool isEmpty()
    {
        return size() == 0;
    }

    bool contains(T o)
    {
        for (auto it = iterator(); it.hasNext();)
            if (javaEquals(it.next(), o))
                return true;
        return false;
    }

    bool containsAll(Collection!T c)
    {
        for (auto it = c.iterator(); it.hasNext();)
            if (!contains(it.next()))
                return false;
        return true;
    }

    bool remove(T o)
    {
        for (auto it = iterator(); it.hasNext();)
            if (javaEquals(it.next(), o))
            {
                it.remove();
                return true;
            }
        return false;
    }

    bool addAll(Collection!T c)
    {
        bool changed;
        foreach (e; c.toArray())
            changed |= add(e);
        return changed;
    }

    bool removeAll(Collection!T c)
    {
        return removeIf((T e) => c.contains(e));
    }

    bool retainAll(Collection!T c)
    {
        return removeIf((T e) => !c.contains(e));
    }

    bool removeIf(bool delegate(T) @safe filter)
    {
        bool changed;
        for (auto it = iterator(); it.hasNext();)
            if (filter(it.next()))
            {
                it.remove();
                changed = true;
            }
        return changed;
    }

    void clear()
    {
        for (auto it = iterator(); it.hasNext();)
        {
            it.next();
            it.remove();
        }
    }

    T[] toArray()
    {
        T[] result;
        result.reserve(size());
        for (auto it = iterator(); it.hasNext();)
            result ~= it.next();
        return result;
    }

    void forEach(void delegate(T) @safe action)
    {
        for (auto it = iterator(); it.hasNext();)
            action(it.next());
    }

    int opApply(scope int delegate(T) @safe dg)
    {
        for (auto it = iterator(); it.hasNext();)
            if (const result = dg(it.next()))
                return result;
        return 0;
    }

    Any[] toAnyArray()
    {
        Any[] result;
        result.reserve(size());
        for (auto it = iterator(); it.hasNext();)
            result ~= Any.of(it.next());
        return result;
    }

    void addAny(Any element)
    {
        add(element.get!T);
    }

    bool isSet()
    {
        return false;
    }

    bool equals(Object o)
    {
        return o is this;
    }

    int hashCode()
    {
        return cast(int)(cast(size_t) cast(const(void)*) this);
    }
}

/// The reversed view: every first/last operation swaps ends, and iteration runs backwards.
private final class ReversedDeque(T) : DequeViewBase!T
{
    private Deque!T original;

    this(Deque!T original) pure nothrow @nogc
    {
        this.original = original;
    }

    alias remove = DequeViewBase!T.remove;

    override bool add(T e)
    {
        original.addFirst(e);
        return true;
    }

    bool offer(T e)
    {
        return original.offerFirst(e);
    }

    T remove()
    {
        return original.removeLast();
    }

    T poll()
    {
        return original.pollLast();
    }

    T element()
    {
        return original.getLast();
    }

    T peek()
    {
        return original.peekLast();
    }

    int size()
    {
        return original.size();
    }

    string elementTypeName()
    {
        return original.elementTypeName();
    }

    Iterator!T iterator()
    {
        return original.descendingIterator();
    }

    void addFirst(T e)
    {
        original.addLast(e);
    }

    void addLast(T e)
    {
        original.addFirst(e);
    }

    bool offerFirst(T e)
    {
        return original.offerLast(e);
    }

    bool offerLast(T e)
    {
        return original.offerFirst(e);
    }

    T removeFirst()
    {
        return original.removeLast();
    }

    T removeLast()
    {
        return original.removeFirst();
    }

    T pollFirst()
    {
        return original.pollLast();
    }

    T pollLast()
    {
        return original.pollFirst();
    }

    T getFirst()
    {
        return original.getLast();
    }

    T getLast()
    {
        return original.getFirst();
    }

    T peekFirst()
    {
        return original.peekLast();
    }

    T peekLast()
    {
        return original.peekFirst();
    }

    bool removeFirstOccurrence(T o)
    {
        return original.removeLastOccurrence(o);
    }

    bool removeLastOccurrence(T o)
    {
        return original.removeFirstOccurrence(o);
    }

    void push(T e)
    {
        original.addLast(e);
    }

    T pop()
    {
        return original.removeLast();
    }

    Iterator!T descendingIterator()
    {
        return original.iterator();
    }
}
