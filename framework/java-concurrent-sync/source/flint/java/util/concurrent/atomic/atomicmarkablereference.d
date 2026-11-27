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
// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/concurrent/atomic/AtomicMarkableReference.java
// Modified by the Flint authors.
module flint.java.util.concurrent.atomic.atomicmarkablereference;

import flint.conc.slot : ProcessSlot;

@safe:

/**
 * A nullable reference to a mutable D object and a mark bit, updated atomically together (R1, R5).
 *
 * Each update publishes a new immutable [reference, mark] pair, as Java's implementation does.
 */
class AtomicMarkableReference(T)
        if ((is(T == class) || is(T == interface)) && !is(T == const) && !is(T == immutable)
            && !is(T == shared) && !is(T == inout) && __traits(getLinkage, T) == "D")
{
    private static final class Pair
    {
        T reference;
        bool mark;

        this(T reference, bool mark) nothrow @nogc
        {
            this.reference = reference;
            this.mark = mark;
        }
    }

    private shared ProcessSlot!Pair pair;

    /// Starts with the given reference and mark.
    this(T initialRef, bool initialMark) nothrow
    {
        pair.setVolatile(new Pair(initialRef, initialMark));
    }

    /// The current reference.
    final T getReference() nothrow @nogc
    {
        return pair.getVolatile().reference;
    }

    /// The current mark.
    final bool isMarked() nothrow @nogc
    {
        return pair.getVolatile().mark;
    }

    /// Replaces both values if the reference has the expected identity and the mark is the expected mark.
    final bool weakCompareAndSet(T expectedReference, T newReference, bool expectedMark, bool newMark) nothrow
    {
        return compareAndSet(expectedReference, newReference, expectedMark, newMark);
    }

    /// Replaces both values if the reference has the expected identity and the mark is the expected mark.
    final bool compareAndSet(T expectedReference, T newReference, bool expectedMark, bool newMark) nothrow
    {
        Pair current = pair.getVolatile();
        return expectedReference is current.reference && expectedMark == current.mark
            && ((newReference is current.reference && newMark == current.mark)
                    || pair.compareAndSet(current, new Pair(newReference, newMark)));
    }

    /// Sets both values unconditionally.
    final void set(T newReference, bool newMark) nothrow
    {
        Pair current = pair.getVolatile();
        if (newReference !is current.reference || newMark != current.mark)
            pair.setVolatile(new Pair(newReference, newMark));
    }

    /// Sets the mark if the reference has the expected identity.
    final bool attemptMark(T expectedReference, bool newMark) nothrow
    {
        Pair current = pair.getVolatile();
        return expectedReference is current.reference && (newMark == current.mark
                || pair.compareAndSet(current, new Pair(expectedReference, newMark)));
    }
}
