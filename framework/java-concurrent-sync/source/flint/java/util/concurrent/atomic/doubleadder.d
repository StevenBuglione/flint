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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/util/concurrent/atomic/DoubleAdder.java
// Modified by the Flint authors.
module flint.java.util.concurrent.atomic.doubleadder;

import flint.java.util.concurrent.atomic.internal.striped64 : Striped64;

@safe:

/**
 * A double sum that scales under contention: concurrent updates spread over padded cells (R1).
 *
 * `sum` is not an atomic snapshot, and the order of the additions, which floating-point rounding depends on,
 * is not defined.
 */
class DoubleAdder : Striped64
{
    /// Starts at zero.
    this() nothrow @nogc
    {
    }

    /// Adds `x`.
    void add(double x) nothrow
    {
        addBits(true, rawBits(x));
    }

    /// The current total of the base and every cell.
    double sum() nothrow @nogc
    {
        return fromBits(sumBits(true));
    }

    /// Resets the total to positive zero. Only exact when no update runs at the same time.
    void reset() nothrow @nogc
    {
        resetCells();
    }

    /// The total, resetting the base and every cell to positive zero as it reads them.
    double sumThenReset() nothrow @nogc
    {
        return fromBits(sumThenResetBits(true));
    }

    /// The total as Java's `Double.toString(sum())` writes it.
    override string toString() nothrow
    {
        import flint.serde.java_number : javaDoubleString;

        return javaDoubleString(sum());
    }

    /// The total.
    override double doubleValue() nothrow @nogc
    {
        return sum();
    }

    /// The total as Java's `(long)` cast converts it: toward zero, NaN as zero, saturated at the limits.
    override long longValue() nothrow @nogc
    {
        const total = sum();
        if (total != total)
            return 0;
        if (total >= 0x1p63)
            return long.max;
        if (total <= -0x1p63)
            return long.min;
        return cast(long) total;
    }

    /// The total as Java's `(int)` cast converts it: toward zero, NaN as zero, saturated at the limits.
    override int intValue() nothrow @nogc
    {
        const total = sum();
        if (total != total)
            return 0;
        if (total >= 0x1p31)
            return int.max;
        if (total <= -0x1p31)
            return int.min;
        return cast(int) total;
    }

    /// The total as a float.
    override float floatValue() nothrow @nogc
    {
        return cast(float) sum();
    }
}
