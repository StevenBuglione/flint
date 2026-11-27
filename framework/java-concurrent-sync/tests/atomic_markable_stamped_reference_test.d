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

// Ported from openjdk 21.0.13: test/jdk/java/util/concurrent/tck/AtomicMarkableReferenceTest.java
// and test/jdk/java/util/concurrent/tck/AtomicStampedReferenceTest.java
// Modified by the Flint authors.
module atomic_markable_stamped_reference_test;

import core.thread.osthread : Thread; // ADR-026 requires the declaring module on DMD for Windows.
import core.time : MonoTime;
import flint.java.util.concurrent.atomic.atomicmarkablereference : AtomicMarkableReference;
import flint.java.util.concurrent.atomic.atomicstampedreference : AtomicStampedReference;

@safe:

private interface Valued
{
    int value() const;
}

private final class Item : Valued
{
    private const int v;

    this(int v)
    {
        this.v = v;
    }

    override int value() const
    {
        return v;
    }
}

// Module variables are thread-local in D, so threaded tests make their own items.
private Item one, two, three, minusThree;

static this()
{
    one = new Item(1);
    two = new Item(2);
    three = new Item(3);
    minusThree = new Item(-3);
}

@system private void joinWithin(Thread t)
{
    const deadline = MonoTime.currTime.ticks + 10 * MonoTime.ticksPerSecond;
    while (t.isRunning)
    {
        assert(MonoTime.currTime.ticks < deadline, "thread did not finish");
        Thread.yield();
    }
    t.join();
}

@("AtomicMarkableReference accepts only mutable D class and interface references")
unittest
{
    static assert(!is(AtomicMarkableReference!int));
    static assert(!is(AtomicMarkableReference!(const Item)));
    static assert(!is(AtomicStampedReference!(immutable Item)));
    static assert(is(AtomicMarkableReference!Valued));
    static assert(is(AtomicStampedReference!Valued));
}

@("AtomicMarkableReference testConstructor")
unittest
{
    auto ai = new AtomicMarkableReference!Item(one, false);
    assert(ai.getReference() is one);
    assert(!ai.isMarked());
    auto a2 = new AtomicMarkableReference!Item(null, true);
    assert(a2.getReference() is null);
    assert(a2.isMarked());
}

@("AtomicMarkableReference testGetSet")
unittest
{
    auto ai = new AtomicMarkableReference!Item(one, false);
    assert(ai.getReference() is one);
    assert(!ai.isMarked());
    ai.set(two, false);
    assert(ai.getReference() is two);
    assert(!ai.isMarked());
    ai.set(one, true);
    assert(ai.getReference() is one);
    assert(ai.isMarked());
}

@("AtomicMarkableReference testAttemptMark")
unittest
{
    auto ai = new AtomicMarkableReference!Item(one, false);
    assert(!ai.isMarked());
    assert(ai.attemptMark(one, true));
    assert(ai.isMarked());
    assert(ai.getReference() is one);
    assert(ai.attemptMark(one, true), "an unchanged mark succeeds without a swap");
    assert(!ai.attemptMark(two, false), "a different identity fails");
    assert(ai.isMarked());
}

@("AtomicMarkableReference testCompareAndSet")
unittest
{
    auto ai = new AtomicMarkableReference!Item(one, false);
    assert(ai.getReference() is one);
    assert(!ai.isMarked());
    assert(ai.compareAndSet(one, two, false, false));
    assert(ai.getReference() is two);
    assert(!ai.isMarked());
    assert(ai.compareAndSet(two, minusThree, false, true));
    assert(ai.getReference() is minusThree);
    assert(ai.isMarked());
    assert(!ai.compareAndSet(two, minusThree, true, true));
    assert(ai.getReference() is minusThree);
    assert(ai.isMarked());
}

@("AtomicMarkableReference compares references by identity, not equality")
unittest
{
    auto equalToOne = new Item(1);
    auto ai = new AtomicMarkableReference!Valued(one, false);
    assert(!ai.compareAndSet(equalToOne, two, false, false));
    assert(ai.getReference() is one);
}

@("AtomicMarkableReference testCompareAndSetInMultipleThreads")
@system unittest
{
    auto one = new Item(1), two = new Item(2), three = new Item(3);
    auto ai = new AtomicMarkableReference!Item(one, false);
    auto t = new Thread(() {
        while (!ai.compareAndSet(two, three, false, false))
            Thread.yield();
    });
    t.start();
    assert(ai.compareAndSet(one, two, false, false));
    joinWithin(t);
    assert(ai.getReference() is three);
    assert(!ai.isMarked());
}

@("AtomicMarkableReference testCompareAndSetInMultipleThreads2")
@system unittest
{
    auto one = new Item(1);
    auto ai = new AtomicMarkableReference!Item(one, false);
    auto t = new Thread(() {
        while (!ai.compareAndSet(one, one, true, false))
            Thread.yield();
    });
    t.start();
    assert(ai.compareAndSet(one, one, false, true));
    joinWithin(t);
    assert(ai.getReference() is one);
    assert(!ai.isMarked());
}

@("AtomicMarkableReference testWeakCompareAndSet")
unittest
{
    auto ai = new AtomicMarkableReference!Item(one, false);
    while (!ai.weakCompareAndSet(one, two, false, false))
    {
    }
    assert(ai.getReference() is two);
    assert(!ai.isMarked());
    while (!ai.weakCompareAndSet(two, minusThree, false, true))
    {
    }
    assert(ai.getReference() is minusThree);
    assert(ai.isMarked());
}

@("AtomicStampedReference testConstructor")
unittest
{
    auto ai = new AtomicStampedReference!Item(one, 0);
    assert(ai.getReference() is one);
    assert(ai.getStamp() == 0);
    auto a2 = new AtomicStampedReference!Item(null, 1);
    assert(a2.getReference() is null);
    assert(a2.getStamp() == 1);
}

@("AtomicStampedReference testGetSet")
unittest
{
    auto ai = new AtomicStampedReference!Item(one, 0);
    assert(ai.getReference() is one);
    assert(ai.getStamp() == 0);
    ai.set(two, 0);
    assert(ai.getReference() is two);
    assert(ai.getStamp() == 0);
    ai.set(one, 1);
    assert(ai.getReference() is one);
    assert(ai.getStamp() == 1);
}

@("AtomicStampedReference testAttemptStamp")
unittest
{
    auto ai = new AtomicStampedReference!Item(one, 0);
    assert(ai.getStamp() == 0);
    assert(ai.attemptStamp(one, 1));
    assert(ai.getStamp() == 1);
    assert(ai.getReference() is one);
    assert(!ai.attemptStamp(two, 2));
    assert(ai.getStamp() == 1);
}

@("AtomicStampedReference testCompareAndSet")
unittest
{
    auto ai = new AtomicStampedReference!Item(one, 0);
    assert(ai.getReference() is one);
    assert(ai.getStamp() == 0);
    assert(ai.compareAndSet(one, two, 0, 0));
    assert(ai.getReference() is two);
    assert(ai.getStamp() == 0);
    assert(ai.compareAndSet(two, minusThree, 0, 1));
    assert(ai.getReference() is minusThree);
    assert(ai.getStamp() == 1);
    assert(!ai.compareAndSet(two, minusThree, 1, 1));
    assert(ai.getReference() is minusThree);
    assert(ai.getStamp() == 1);
}

@("AtomicStampedReference testCompareAndSetInMultipleThreads")
@system unittest
{
    auto one = new Item(1), two = new Item(2), three = new Item(3);
    auto ai = new AtomicStampedReference!Item(one, 0);
    auto t = new Thread(() {
        while (!ai.compareAndSet(two, three, 0, 0))
            Thread.yield();
    });
    t.start();
    assert(ai.compareAndSet(one, two, 0, 0));
    joinWithin(t);
    assert(ai.getReference() is three);
    assert(ai.getStamp() == 0);
}

@("AtomicStampedReference testCompareAndSetInMultipleThreads2")
@system unittest
{
    auto one = new Item(1);
    auto ai = new AtomicStampedReference!Item(one, 0);
    auto t = new Thread(() {
        while (!ai.compareAndSet(one, one, 1, 2))
            Thread.yield();
    });
    t.start();
    assert(ai.compareAndSet(one, one, 0, 1));
    joinWithin(t);
    assert(ai.getReference() is one);
    assert(ai.getStamp() == 2);
}

@("AtomicStampedReference testWeakCompareAndSet")
unittest
{
    auto ai = new AtomicStampedReference!Item(one, 0);
    while (!ai.weakCompareAndSet(one, two, 0, 0))
    {
    }
    assert(ai.getReference() is two);
    assert(ai.getStamp() == 0);
    while (!ai.weakCompareAndSet(two, minusThree, 0, 1))
    {
    }
    assert(ai.getReference() is minusThree);
    assert(ai.getStamp() == 1);
}

@("AtomicStampedReference ABA: a stamp change defeats a stale compareAndSet")
unittest
{
    auto ai = new AtomicStampedReference!Item(one, 0);
    assert(ai.compareAndSet(one, two, 0, 1));
    assert(ai.compareAndSet(two, one, 1, 2));
    assert(!ai.compareAndSet(one, three, 0, 1), "same reference, stale stamp");
    assert(ai.getReference() is one);
    assert(ai.getStamp() == 2);
}

@("Concurrent increments through compareAndSet lose no stamp update")
@system unittest
{
    enum perThread = 2000;
    auto one = new Item(1), two = new Item(2);
    auto ai = new AtomicStampedReference!Item(one, 0);
    void work()
    {
        foreach (_; 0 .. perThread)
        {
            for (;;)
            {
                const s = ai.getStamp();
                auto r = ai.getReference();
                if (ai.compareAndSet(r, r is one ? two : one, s, s + 1))
                    break;
            }
        }
    }

    auto a = new Thread(&work), b = new Thread(&work);
    a.start();
    b.start();
    joinWithin(a);
    joinWithin(b);
    assert(ai.getStamp() == 2 * perThread);
    assert(ai.getReference() is one);
}
