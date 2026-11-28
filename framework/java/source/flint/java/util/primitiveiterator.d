/*
 * Copyright (c) 2013, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/PrimitiveIterator.java
// Modified by the Flint authors.

module flint.java.util.primitiveiterator;

import flint.java.util : Iterator;
import flint.java.util.function_.doubleconsumer : DoubleConsumer;
import flint.java.util.function_.intconsumer : IntConsumer;
import flint.java.util.function_.longconsumer : LongConsumer;

@safe:

/**
 * An iterator over primitive values that hands them to a primitive consumer.
 *
 * `OfInt`, `OfLong` and `OfDouble` are hoisted out of the template as
 * `PrimitiveIteratorOfInt` and its siblings and aliased back (R13). Java's boxed
 * `next()` returns the primitive (R5), and a `null` action throws
 * `NullPointerException` before the first element is taken.
 */
interface PrimitiveIterator(T, TCons) : Iterator!T
{
    /// Perform `action` on each remaining element, in order, until none remain.
    void forEachRemaining(TCons action);

    /// Keep the canonical boxed `forEachRemaining(Consumer!T)` in the overload set (R5).
    alias forEachRemaining = Iterator!T.forEachRemaining;

    /// Java's `PrimitiveIterator.OfInt` (R13).
    alias OfInt = PrimitiveIteratorOfInt;
    /// Java's `PrimitiveIterator.OfLong` (R13).
    alias OfLong = PrimitiveIteratorOfLong;
    /// Java's `PrimitiveIterator.OfDouble` (R13).
    alias OfDouble = PrimitiveIteratorOfDouble;
}

/// Java's `PrimitiveIterator.OfInt`, hoisted out of `PrimitiveIterator` (R13).
interface PrimitiveIteratorOfInt : PrimitiveIterator!(int, IntConsumer)
{
    /// The next element. Throws `NoSuchElementException` at the end.
    int nextInt();

    /// R9 delegate form of `forEachRemaining(IntConsumer)`.
    final void forEachRemaining(void delegate(int) @safe action)
    {
        if (action is null)
            nullAction();
        while (hasNext())
            action(nextInt());
    }

    alias forEachRemaining = PrimitiveIterator!(int, IntConsumer).forEachRemaining;

    /// R3 implementation of the Java default methods.
    mixin template Defaults(Action = IntConsumer, alias Of = PrimitiveIteratorOfInt)
    {
        alias forEachRemaining = Of.forEachRemaining;

        void forEachRemaining(Action action)
        {
            Of self = this;
            self.forEachRemaining(action is null ? null : action.asDelegate());
        }

        int next()
        {
            return nextInt();
        }
    }
}

/// Java's `PrimitiveIterator.OfLong`, hoisted out of `PrimitiveIterator` (R13).
interface PrimitiveIteratorOfLong : PrimitiveIterator!(long, LongConsumer)
{
    /// The next element. Throws `NoSuchElementException` at the end.
    long nextLong();

    /// R9 delegate form of `forEachRemaining(LongConsumer)`.
    final void forEachRemaining(void delegate(long) @safe action)
    {
        if (action is null)
            nullAction();
        while (hasNext())
            action(nextLong());
    }

    alias forEachRemaining = PrimitiveIterator!(long, LongConsumer).forEachRemaining;

    /// R3 implementation of the Java default methods.
    mixin template Defaults(Action = LongConsumer, alias Of = PrimitiveIteratorOfLong)
    {
        alias forEachRemaining = Of.forEachRemaining;

        void forEachRemaining(Action action)
        {
            Of self = this;
            self.forEachRemaining(action is null ? null : action.asDelegate());
        }

        long next()
        {
            return nextLong();
        }
    }
}

/// Java's `PrimitiveIterator.OfDouble`, hoisted out of `PrimitiveIterator` (R13).
interface PrimitiveIteratorOfDouble : PrimitiveIterator!(double, DoubleConsumer)
{
    /// The next element. Throws `NoSuchElementException` at the end.
    double nextDouble();

    /// R9 delegate form of `forEachRemaining(DoubleConsumer)`.
    final void forEachRemaining(void delegate(double) @safe action)
    {
        if (action is null)
            nullAction();
        while (hasNext())
            action(nextDouble());
    }

    alias forEachRemaining = PrimitiveIterator!(double, DoubleConsumer).forEachRemaining;

    /// R3 implementation of the Java default methods.
    mixin template Defaults(Action = DoubleConsumer, alias Of = PrimitiveIteratorOfDouble)
    {
        alias forEachRemaining = Of.forEachRemaining;

        void forEachRemaining(Action action)
        {
            Of self = this;
            self.forEachRemaining(action is null ? null : action.asDelegate());
        }

        double next()
        {
            return nextDouble();
        }
    }
}

// Objects.requireNonNull(action), kept out of line so each loop stays small (R8).
pragma(inline, false) private noreturn nullAction()
{
    import flint.java.lang : NullPointerException;

    throw new NullPointerException(cast(string) null);
}
