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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/concurrent/atomic/LongAdder.java
// Modified by the Flint authors.
module flint.java.util.concurrent.atomic.longadder;

import flint.java.util.concurrent.atomic.internal.striped64 : Striped64;

@safe:

/**
 * A long sum that scales under contention: concurrent updates spread over padded cells (R1).
 *
 * `sum` is not an atomic snapshot: updates that run while it reads may or may not be counted.
 */
class LongAdder : Striped64
{
    /// Starts at zero.
    this() nothrow @nogc
    {
    }

    /// Adds `x`.
    void add(long x) nothrow
    {
        addBits(false, x);
    }

    /// Adds one.
    void increment() nothrow
    {
        add(1L);
    }

    /// Subtracts one.
    void decrement() nothrow
    {
        add(-1L);
    }

    /// The current total of the base and every cell.
    long sum() nothrow @nogc
    {
        return sumBits(false);
    }

    /// Resets the total to zero. Only exact when no update runs at the same time.
    void reset() nothrow @nogc
    {
        resetCells();
    }

    /// The total, resetting the base and every cell to zero as it reads them.
    long sumThenReset() nothrow @nogc
    {
        return sumThenResetBits(false);
    }

    /// The decimal total, as Java's `Long.toString(sum())`.
    override string toString() nothrow
    {
        import flint.engine.aot.text : decimal;

        return decimal(sum());
    }

    /// The total.
    override long longValue() nothrow @nogc
    {
        return sum();
    }

    /// The total, narrowed to its low 32 bits.
    override int intValue() nothrow @nogc
    {
        return cast(int) sum();
    }

    /// The total as a float.
    override float floatValue() nothrow @nogc
    {
        return cast(float) sum();
    }

    /// The total as a double.
    override double doubleValue() nothrow @nogc
    {
        return cast(double) sum();
    }
}

@("LongAdder creates and grows its cell table and sums every cell")
unittest
{
    auto a = new LongAdder();
    a.accumulate(false, 5, true, 1);
    assert(a.length.get() == 2, "the first contended update creates the table with two cells in use");
    assert(a.cell(1, 2).get() == 5 && a.cell(0, 2).get() == 0);
    assert(a.table.limit >= 2 && a.table.limit <= Striped64.maxCells);
    a.accumulate(false, 11, true, 2);
    a.accumulate(false, 7, false, 1);
    a.add(100);
    assert(a.sum() == 123 && a.longValue() == 123);
    assert(a.base.get() == 0, "with a table, updates go to cells");

    const first = a.cell(0, 2).get(), second = a.cell(1, 2).get();
    a.length.set(4);
    assert(a.cell(0, 4).get() == first && a.cell(1, 4).get() == second, "growing keeps every cell in place");
    assert(a.cell(2, 4).get() == 0 && a.cell(3, 4).get() == 0);
    a.accumulate(false, 1000, true, 3);
    assert(a.sum() == 1123);

    assert(a.sumThenReset() == 1123 && a.sum() == 0);
    a.add(-4);
    a.reset();
    assert(a.sum() == 0);
}

@("A cell fills one 64-byte line, so two cells never share a cache line")
unittest
{
    assert(Striped64.Cell.sizeof == 64);
    assert(Striped64.Cells.cells.offsetof % 16 == 0);
    assert(Striped64.getProbe() != 0);
    assert(Striped64.advanceProbe(1) != 1 && Striped64.advanceProbe(1) != 0);
}
