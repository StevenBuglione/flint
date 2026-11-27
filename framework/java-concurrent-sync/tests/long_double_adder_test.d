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

// Ported from openjdk 21.0.13: test/jdk/java/util/concurrent/tck/LongAdderTest.java
// and test/jdk/java/util/concurrent/tck/DoubleAdderTest.java
// Modified by the Flint authors.
module long_double_adder_test;

import core.thread.osthread : Thread; // ADR-026 requires the declaring module on DMD for Windows.
import core.time : MonoTime;
import flint.java.lang.number : Number;
import flint.java.util.concurrent.atomic.doubleadder : DoubleAdder;
import flint.java.util.concurrent.atomic.longadder : LongAdder;

@safe:

@system private void joinWithin(Thread t)
{
    const deadline = MonoTime.currTime.ticks + 60 * MonoTime.ticksPerSecond;
    while (t.isRunning)
    {
        assert(MonoTime.currTime.ticks < deadline, "thread did not finish");
        Thread.yield();
    }
    t.join();
}

@("LongAdder testConstructor")
unittest
{
    auto ai = new LongAdder();
    assert(ai.sum() == 0);
}

@("LongAdder testAddAndSum")
unittest
{
    auto ai = new LongAdder();
    ai.add(2);
    assert(ai.sum() == 2);
    ai.add(-4);
    assert(ai.sum() == -2);
}

@("LongAdder testDecrementAndSum")
unittest
{
    auto ai = new LongAdder();
    ai.decrement();
    assert(ai.sum() == -1);
    ai.decrement();
    assert(ai.sum() == -2);
}

@("LongAdder testIncrementAndSum")
unittest
{
    auto ai = new LongAdder();
    ai.increment();
    assert(ai.sum() == 1);
    ai.increment();
    assert(ai.sum() == 2);
}

@("LongAdder testReset")
unittest
{
    auto ai = new LongAdder();
    ai.add(2);
    assert(ai.sum() == 2);
    ai.reset();
    assert(ai.sum() == 0);
}

@("LongAdder testSumThenReset")
unittest
{
    auto ai = new LongAdder();
    ai.add(2);
    assert(ai.sum() == 2);
    assert(ai.sumThenReset() == 2);
    assert(ai.sum() == 0);
}

@("LongAdder testToString")
unittest
{
    auto ai = new LongAdder();
    assert(ai.toString() == "0");
    ai.increment();
    assert(ai.toString() == "1");
    ai.add(long.min);
    assert(ai.toString() == "-9223372036854775807");
}

@("LongAdder testIntValue, testLongValue, testFloatValue and testDoubleValue")
unittest
{
    auto ai = new LongAdder();
    assert(ai.intValue() == 0 && ai.longValue() == 0 && ai.floatValue() == 0.0f && ai.doubleValue() == 0.0);
    ai.increment();
    assert(ai.intValue() == 1 && ai.longValue() == 1 && ai.floatValue() == 1.0f && ai.doubleValue() == 1.0);
}

@("LongAdder is a Number, with Java's narrowing conversions")
unittest
{
    auto ai = new LongAdder();
    ai.add(0x1_0000_0001L);
    Number n = ai;
    assert(n.longValue() == 0x1_0000_0001L);
    assert(n.intValue() == 1);
    assert(n.shortValue() == 1 && n.byteValue() == 1);
    ai.add(long.max);
    assert(n.longValue() == long.min + 0x1_0000_0000L, "the sum wraps as Java's long addition does");
}

@("LongAdder testAddAndSumMT")
@system unittest
{
    enum incs = 200_000;
    enum nthreads = 4;
    auto a = new LongAdder();
    Thread[nthreads] threads;
    foreach (ref t; threads)
        t = new Thread(() {
            foreach (_; 0 .. incs)
                a.add(1L);
        }).start();
    foreach (t; threads)
        joinWithin(t);
    assert(a.sum() == long(nthreads) * incs);
    assert(a.sumThenReset() == long(nthreads) * incs);
    assert(a.sum() == 0);
}

@("LongAdder keeps every update while concurrent increments and decrements contend")
@system unittest
{
    enum incs = 100_000;
    auto a = new LongAdder();
    auto up = new Thread(() {
        foreach (_; 0 .. incs)
            a.increment();
    });
    auto down = new Thread(() {
        foreach (_; 0 .. incs)
            a.decrement();
    });
    auto adds = new Thread(() {
        foreach (_; 0 .. incs)
            a.add(3);
    });
    up.start();
    down.start();
    adds.start();
    joinWithin(up);
    joinWithin(down);
    joinWithin(adds);
    assert(a.sum() == 3L * incs);
}

@("DoubleAdder testConstructor")
unittest
{
    auto ai = new DoubleAdder();
    assert(ai.sum() == 0.0);
}

@("DoubleAdder testAddAndSum")
unittest
{
    auto ai = new DoubleAdder();
    ai.add(2.0);
    assert(ai.sum() == 2.0);
    ai.add(-4.0);
    assert(ai.sum() == -2.0);
}

@("DoubleAdder testReset")
unittest
{
    auto ai = new DoubleAdder();
    ai.add(2.0);
    assert(ai.sum() == 2.0);
    ai.reset();
    assert(ai.sum() == 0.0);
}

@("DoubleAdder testSumThenReset")
unittest
{
    auto ai = new DoubleAdder();
    ai.add(2.0);
    assert(ai.sum() == 2.0);
    assert(ai.sumThenReset() == 2.0);
    assert(ai.sum() == 0.0);
}

@("DoubleAdder testToString")
unittest
{
    auto ai = new DoubleAdder();
    assert(ai.toString() == "0.0");
    ai.add(1.0);
    assert(ai.toString() == "1.0");
    ai.add(1e20);
    assert(ai.toString() == "1.0E20");
}

@("DoubleAdder testIntValue, testLongValue, testFloatValue and testDoubleValue")
unittest
{
    auto ai = new DoubleAdder();
    assert(ai.intValue() == 0 && ai.longValue() == 0 && ai.floatValue() == 0.0f && ai.doubleValue() == 0.0);
    ai.add(1.0);
    assert(ai.intValue() == 1 && ai.longValue() == 1 && ai.floatValue() == 1.0f && ai.doubleValue() == 1.0);
}

@("DoubleAdder converts to int and long as Java's casts do")
unittest
{
    auto ai = new DoubleAdder();
    ai.add(-2.75);
    assert(ai.intValue() == -2 && ai.longValue() == -2, "toward zero");
    ai.reset();
    ai.add(double.nan);
    assert(ai.intValue() == 0 && ai.longValue() == 0, "NaN converts to zero");
    assert(ai.toString() == "NaN");
    ai.reset();
    ai.add(1e300);
    assert(ai.intValue() == int.max && ai.longValue() == long.max);
    ai.reset();
    ai.add(-double.infinity);
    assert(ai.intValue() == int.min && ai.longValue() == long.min);
    assert(ai.toString() == "-Infinity");
}

@("DoubleAdder reset leaves positive zero")
unittest
{
    auto ai = new DoubleAdder();
    ai.add(-0.0);
    ai.reset();
    assert(ai.toString() == "0.0");
    ai.add(-5.0);
    assert(ai.sumThenReset() == -5.0);
    assert(ai.toString() == "0.0");
}

@("DoubleAdder testAddAndSumMT")
@system unittest
{
    enum incs = 200_000;
    enum nthreads = 4;
    auto a = new DoubleAdder();
    Thread[nthreads] threads;
    foreach (ref t; threads)
        t = new Thread(() {
            foreach (_; 0 .. incs)
                a.add(1.0);
        }).start();
    foreach (t; threads)
        joinWithin(t);
    assert(a.sum() == double(long(nthreads) * incs));
}
