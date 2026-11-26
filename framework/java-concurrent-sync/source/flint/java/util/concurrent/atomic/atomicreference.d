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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/concurrent/atomic/AtomicReference.java
// Modified by the Flint authors.
module flint.java.util.concurrent.atomic.atomicreference;

import flint.conc.slot : ProcessSlot;
import std.traits : Unqual;

@safe:

/// An atomically published, nullable reference to a mutable D object (R1, R5).
class AtomicReference(T)
        if ((is(T == class) || is(T == interface)) && is(T == Unqual!T) && __traits(getLinkage, T) == "D")
{
    private shared ProcessSlot!T slot;

    /// Starts with a null reference.
    this() nothrow @nogc
    {
    }

    /// Starts with the given reference.
    this(T initialValue) nothrow @nogc
    {
        slot.set(initialValue);
    }

    /// Loads the reference with acquire ordering.
    final T getAcquire() nothrow @nogc
    {
        return slot.get();
    }

    /// Publishes the reference with release ordering.
    final void setRelease(T newValue) nothrow @nogc
    {
        slot.set(newValue);
    }

    /// Publishes the reference with release ordering.
    final void lazySet(T newValue) nothrow @nogc
    {
        setRelease(newValue);
    }
}
