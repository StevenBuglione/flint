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

// Modified by the Flint authors: the set is a thin adapter over CopyOnWriteArrayList, as in Java. Every read sees
// the list's published snapshot; every write copies under the list's mutex. This is a class with no subclasses in
// Java, so it is a class here too; the generics are D templates.
module flint.java.util.concurrent.copyonwritearrayset;

import flint.java.lang : javaEquals, javaHashCode;
import flint.java.util : AbstractCollection, Collection, Iterator, Set;
import flint.java.util.concurrent.copyonwritearraylist : CopyOnWriteArrayList;

@safe:

/++
A thread-safe `Set` backed by a `CopyOnWriteArrayList`. Reads never lock and see the snapshot published when they
started; writes copy under the list's mutex. Iteration is over a snapshot, so a caller never sees a concurrent
write. Duplicate elements are rejected by `add` and `addAll`, as in Java.
+/
class CopyOnWriteArraySet(T) : AbstractCollection!T, Set!T
{
    /// Descriptor hook: the storage is private, not JSON fields.
    enum __flintOpaque = true;

    private CopyOnWriteArrayList!T al;

    /// An empty set.
    this()
    {
        al = new CopyOnWriteArrayList!T;
    }

    /// A set holding the distinct elements of `c`, in its iteration order.
    this(Collection!T c)
    {
        al = new CopyOnWriteArrayList!T;
        al.addAllAbsent(c);
    }

    override int size()
    {
        return al.size();
    }

    override bool isEmpty()
    {
        return al.isEmpty();
    }

    override bool contains(T element)
    {
        return al.contains(element);
    }

    override bool containsAll(Collection!T c)
    {
        return al.containsAll(c);
    }

    override T[] toArray()
    {
        return al.toArray();
    }

    override void clear()
    {
        al.clear();
    }

    override Iterator!T iterator()
    {
        return al.iterator();
    }

    override bool add(T element)
    {
        return al.addIfAbsent(element);
    }

    override bool addAll(Collection!T c)
    {
        return al.addAllAbsent(c) > 0;
    }

    override bool remove(T element)
    {
        return al.remove(element);
    }

    override bool removeAll(Collection!T c)
    {
        return al.removeIf((T e) => c.contains(e));
    }

    override bool retainAll(Collection!T c)
    {
        return al.removeIf((T e) => !c.contains(e));
    }

    override bool removeIf(bool delegate(T) @safe filter)
    {
        return al.removeIf(filter);
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
        auto elements = al.toArray();
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
        foreach (e; al.toArray())
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
