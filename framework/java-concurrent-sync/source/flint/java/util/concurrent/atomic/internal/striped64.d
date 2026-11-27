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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/concurrent/atomic/Striped64.java
// Modified by the Flint authors.
module flint.java.util.concurrent.atomic.internal.striped64;

import flint.conc.word : ProcessWord;
import flint.java.lang.number : Number;

@safe:

/**
 * The striped counter behind LongAdder and DoubleAdder (R1).
 *
 * Updates go to `base` until a compare-and-set on it fails. Contended updates then go to a table of padded
 * cells, indexed by a per-stack probe, whose length doubles on repeated collisions until it reaches the CPU
 * count. A double value is kept as its raw bits.
 *
 * Every word is a `ProcessWord`, whose non-template operations keep `core.atomic`'s instantiations out of
 * this package. The table is one pointer-free object holding all `maxCells` cells inline, so it needs no
 * cast, no array allocation and no per-cell publication. It is published once by `length`, which is zero
 * until the table exists and then doubles in place. LDC emits a package's template instances into its first
 * object, and a cast to or an array of this module's types there would make every probe that links that
 * object also link this module.
 */
package(flint.java.util.concurrent.atomic) abstract class Striped64 : Number
{
    /// The table's capacity: Java grows it up to the CPU count; Flint stops at 16 cells.
    enum maxCells = 16;

    /// One cell. With its padding it fills a 64-byte line, so two cells never share a cache line
    /// (Java's @Contended).
    static struct Cell
    {
        ProcessWord value;
        private long[7] padding;
    }

    /// Every cell, allocated with the first contended update.
    static final class Cells
    {
        shared Cell[maxCells] cells;
        /// Java's NCPU, from 2 to `maxCells`: `length` stops doubling at this size.
        const long limit;

        this(long limit) nothrow @nogc
        {
            this.limit = limit;
        }
    }

    /// The value while there is no contention.
    shared ProcessWord base;
    /// The number of cells in use: zero until `table` exists, then a power of two.
    shared ProcessWord length;
    /// The table, written once under `cellsBusy` before `length` publishes it.
    package(flint.java.util.concurrent.atomic) Cells table;
    /// A spin lock held while the table is created or grown.
    private shared ProcessWord cellsBusy;

    this() nothrow @nogc
    {
    }

    private bool casCellsBusy() nothrow @nogc
    {
        return cellsBusy.get() == 0 && cellsBusy.compareAndSet(0, 1);
    }

    private void releaseCellsBusy() nothrow @nogc
    {
        cellsBusy.set(0);
    }

    /// The cell that `probe` selects among the first `n`, which must be nonzero.
    final ref shared(ProcessWord) cell(int probe, long n) return nothrow @nogc
    {
        return table.cells[cast(size_t)(probe & (n - 1) & (maxCells - 1))].value;
    }

    /// The slot index for this stack. Java keeps a random probe in each Thread; the address of a local is
    /// distinct for every thread and fiber stack, needs no thread-local state, and is never zero here.
    static int getProbe() nothrow @nogc
    {
        int marker;
        const hash = cast(int)(((cast(size_t)&marker >> 4) * 0x9E3779B97F4A7C15UL) >>> 32);
        return hash == 0 ? 1 : hash;
    }

    /// The next probe after a collision: Java's xorshift, kept for the rest of this update.
    static int advanceProbe(int probe) pure nothrow @nogc
    {
        probe ^= probe << 13;
        probe ^= probe >>> 17;
        probe ^= probe << 5;
        return probe;
    }

    /// `v + x`, as longs or as the doubles whose raw bits they hold.
    static long combine(bool doubles, long v, long x) pure nothrow @nogc
    {
        return doubles ? rawBits(fromBits(v) + fromBits(x)) : v + x;
    }

    /// Adds `x` (raw bits when `doubles`): LongAdder.add and DoubleAdder.add. A compare-and-set on `base`
    /// while there is no table, else on this stack's cell, else `accumulate`.
    final void addBits(bool doubles, long x) nothrow
    {
        const n = length.get();
        long b;
        if (n != 0 || !base.compareAndSet(b = base.get(), combine(doubles, b, x)))
        {
            const index = getProbe();
            if (n == 0)
                return accumulate(doubles, x, true, index);
            const v = cell(index, n).get();
            if (!cell(index, n).compareAndSet(v, combine(doubles, v, x)))
                accumulate(doubles, x, false, index);
        }
    }

    /// The total of `base` and every cell, as a long or as raw double bits. Not an atomic snapshot.
    final long sumBits(bool doubles) nothrow @nogc
    {
        return total(doubles, false);
    }

    /// The total, setting `base` and every cell to zero as it reads them.
    final long sumThenResetBits(bool doubles) nothrow @nogc
    {
        return total(doubles, true);
    }

    /// Sets `base` and every cell to zero, which is also positive zero's bits.
    final void resetCells() nothrow @nogc
    {
        const n = length.get();
        base.set(0);
        foreach (i; 0 .. cast(int) n)
            cell(i, n).set(0);
    }

    private long total(bool doubles, bool resetting) nothrow @nogc
    {
        const n = length.get();
        long sum = resetting ? base.getAndSet(0) : base.get();
        foreach (i; 0 .. cast(int) n)
            sum = combine(doubles, sum, resetting ? cell(i, n).getAndSet(0) : cell(i, n).get());
        return sum;
    }

    /// Java's Striped64.longAccumulate and doubleAccumulate without a function: adds `x` (raw bits when
    /// `doubles`) to a cell, creating or growing the table, or falls back to `base`. Every cell exists once
    /// the table does, so Java's step that attaches a new cell to an empty slot has no counterpart.
    final void accumulate(bool doubles, long x, bool wasUncontended, int index) nothrow
    {
        for (bool collide = false;;)
        {
            const n = length.get();
            long v;
            if (n != 0)
            {
                if (!wasUncontended)
                    wasUncontended = true;
                else if (cell(index, n).compareAndSet(v = cell(index, n).get(), combine(doubles, v, x)))
                    return;
                else if (n >= table.limit || length.get() != n)
                    collide = false;
                else if (!collide)
                    collide = true;
                else if (casCellsBusy())
                {
                    length.compareAndSet(n, n << 1);
                    releaseCellsBusy();
                    collide = false;
                    continue;
                }
                index = advanceProbe(index);
            }
            else if (casCellsBusy())
            {
                const created = length.get() == 0;
                if (created)
                {
                    table = new Cells(processors());
                    cell(index, 2).set(x);
                    length.set(2);
                }
                releaseCellsBusy();
                if (created)
                    return;
            }
            else if (base.compareAndSet(v = base.get(), combine(doubles, v, x)))
                return;
        }
    }

    /// The raw bits of `d`.
    static long rawBits(double d) pure nothrow @nogc
    {
        Bits bits;
        bits.d = d;
        return bits.l;
    }

    /// The double whose raw bits are `l`.
    static double fromBits(long l) pure nothrow @nogc
    {
        Bits bits;
        bits.l = l;
        return bits.d;
    }

    /// The online CPU count, at least 2 and at most `maxCells`.
    private static long processors() nothrow @nogc
    {
        long online = 0;
        version (Posix)
        {
            import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;

            online = sysconf(_SC_NPROCESSORS_ONLN);
        }
        return online < 2 ? 2 : online > maxCells ? maxCells : online;
    }
}

private union Bits
{
    double d;
    long l;
}
