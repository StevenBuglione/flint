/*
 * Copyright (c) 2012, 2021, Oracle and/or its affiliates. All rights reserved.
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
 * Copyright (c) 2009-2012, Stephen Colebourne & Michael Nascimento Santos
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *  * Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 *  * Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 *  * Neither the name of JSR-310 nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
// Ported from openjdk 21.0.13: src/java.base/share/classes/java/time/zone/ZoneRules.java
// Modified by the Flint authors.
module flint.java.time.zone.internal.suppliedrules;

import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.time : Instant, LocalDate, LocalDateTime, ZoneOffset;
import flint.java.time.zone.internal.rulestorage : LocalMatch, RuleStorage;
import flint.java.time.zone.zoneoffsettransition : ZoneOffsetTransition;
import flint.java.time.zone.zoneoffsettransitionrule : ZoneOffsetTransitionRule;
import flint.java.util : List;
import std.typecons : Nullable;

@safe:

private enum maxRecurringRules = 16;

package(flint.java.time.zone) immutable(RuleStorage) makeSuppliedRules()(ZoneOffset baseStandardOffset,
        ZoneOffset baseWallOffset,
        List!ZoneOffsetTransition standardTransitions,
        List!ZoneOffsetTransition transitions, List!ZoneOffsetTransitionRule lastRules)
{
    if (standardTransitions is null)
        throw new NullPointerException("standardOffsetTransitionList");
    if (transitions is null)
        throw new NullPointerException("transitionList");
    if (lastRules is null)
        throw new NullPointerException("lastRules");
    if (standardTransitions.isEmpty() && transitions.isEmpty() && lastRules.isEmpty()
            && baseStandardOffset == baseWallOffset)
        return null;

    auto standardEpochs = new long[standardTransitions.size()];
    auto standardOffsets = new ZoneOffset[standardEpochs.length + 1];
    standardOffsets[0] = baseStandardOffset;
    foreach (i, ref epoch; standardEpochs)
    {
        const transition = standardTransitions.get(cast(int) i);
        epoch = transition.toEpochSecond();
        standardOffsets[i + 1] = transition.getOffsetAfter();
    }

    auto wallEpochs = new long[transitions.size()];
    auto wallOffsets = new ZoneOffset[wallEpochs.length + 1];
    auto wallBounds = new LocalDateTime[2 * wallEpochs.length];
    wallOffsets[0] = baseWallOffset;
    foreach (i, ref epoch; wallEpochs)
    {
        const transition = transitions.get(cast(int) i);
        epoch = transition.toEpochSecond();
        wallOffsets[i + 1] = transition.getOffsetAfter();
        const before = transition.getDateTimeBefore();
        const after = transition.getDateTimeAfter();
        wallBounds[2 * i] = transition.isGap() ? before : after;
        wallBounds[2 * i + 1] = transition.isGap() ? after : before;
    }

    const recurring = lastRules.toArray();
    if (recurring.length > maxRecurringRules)
        throw new IllegalArgumentException("Too many transition rules");
    const standardHash = arrayHash(standardEpochs) ^ arrayHash(standardOffsets);
    const wallHash = arrayHash(wallEpochs) ^ arrayHash(wallOffsets);
    const hash = standardHash ^ wallHash ^ arrayHash(recurring);
    return new immutable SuppliedRules!()(RuleData(standardEpochs.idup, standardOffsets.idup,
            wallEpochs.idup, wallOffsets.idup, wallBounds.idup, recurring.idup, hash));
}

private struct RuleData
{
    immutable(long)[] standardEpochs;
    immutable(ZoneOffset)[] standardOffsets;
    immutable(long)[] wallEpochs;
    immutable(ZoneOffset)[] wallOffsets;
    immutable(LocalDateTime)[] wallBounds;
    immutable(ZoneOffsetTransitionRule)[] annual;
    int hash;
}

private final class SuppliedRules() : RuleStorage
{
    private immutable RuleData data_;

    this(immutable RuleData data) immutable pure nothrow @nogc
    {
        data_ = data;
    }

    override bool hasWallChanges() const pure nothrow @nogc
    {
        return data_.wallEpochs.length != 0;
    }

    override bool hasStandardChanges() const pure nothrow @nogc
    {
        return data_.standardEpochs.length != 0;
    }

    override ZoneOffset offsetAt(Instant instant) const
    {
        return suppliedOffset(&data_, instant);
    }

    override ZoneOffset standardAt(Instant instant) const pure nothrow @nogc
    {
        return data_.standardOffsets[bound(data_.standardEpochs, instant.getEpochSecond())];
    }

    override LocalMatch localAt(LocalDateTime dateTime) const
    {
        return suppliedLocal(&data_, dateTime);
    }

    override LocalMatch next(Instant instant) const
    {
        return project(suppliedNext(&data_, instant));
    }

    override LocalMatch previous(Instant instant) const
    {
        return project(suppliedPrevious(&data_, instant));
    }

    override size_t historicCount() const pure nothrow @nogc
    {
        return data_.wallEpochs.length;
    }

    override LocalMatch historic(size_t index) const
    {
        return project(historicTransition(&data_, index));
    }

    override immutable(ZoneOffsetTransitionRule)[] annual() const pure nothrow @nogc
    {
        return data_.annual;
    }

    override bool same(const RuleStorage other) const pure nothrow @nogc
    {
        const supplied = cast(const SuppliedRules) other;
        return supplied !is null && sameRules(&data_, &supplied.data_);
    }

    override int hash() const pure nothrow @nogc
    {
        return data_.hash;
    }

    override ZoneOffset finalStandard() const pure nothrow @nogc
    {
        return data_.standardOffsets[$ - 1];
    }
}

private LocalMatch project()(Nullable!ZoneOffsetTransition value) pure nothrow @nogc
{
    if (value.isNull)
        return LocalMatch.init;
    const transition = value.get();
    return LocalMatch(transition.getOffsetBefore(), transition.getOffsetAfter(), transition.getDateTimeBefore(), true);
}

private ZoneOffset suppliedOffset()(scope const RuleData* data, Instant instant)
{
    const second = instant.getEpochSecond();
    if (data.annual.length && second > data.wallEpochs[$ - 1])
    {
        ZoneOffsetTransition[maxRecurringRules] scratch;
        const annual = recurringIn(data, transitionYear(second, data.wallOffsets[$ - 1]), scratch[]);
        foreach (ref const transition; annual)
            if (second < transition.toEpochSecond())
                return transition.getOffsetBefore();
        return annual[$ - 1].getOffsetAfter();
    }
    return data.wallOffsets[bound(data.wallEpochs, second)];
}

private LocalMatch suppliedLocal()(scope const RuleData* data, LocalDateTime dateTime)
{
    if (data.annual.length && dateTime.isAfter(data.wallBounds[$ - 1]))
    {
        ZoneOffsetTransition[maxRecurringRules] scratch;
        const annual = recurringIn(data, dateTime.getYear(), scratch[]);
        foreach (ref const transition; annual)
        {
            const preferred = transition.getOffsetBefore();
            if (preferred == transition.getOffsetAfter())
                return LocalMatch(preferred);
            const before = transition.getDateTimeBefore();
            const after = transition.getDateTimeAfter();
            const start = transition.isGap() ? before : after;
            const end = transition.isGap() ? after : before;
            if (dateTime.isBefore(start))
                return LocalMatch(preferred);
            if (dateTime.isBefore(end))
                return LocalMatch(preferred, transition.getOffsetAfter(), before, true);
        }
        return LocalMatch(annual[$ - 1].getOffsetAfter());
    }

    const count = bound(data.wallBounds, dateTime);
    const index = count / 2;
    const offset = data.wallOffsets[index];
    if (!(count & 1))
        return LocalMatch(offset);
    const after = data.wallOffsets[index + 1];
    const beforeTime = data.wallBounds[count - (after.getTotalSeconds() > offset.getTotalSeconds())];
    return LocalMatch(offset, after, beforeTime, true);
}

private Nullable!ZoneOffsetTransition suppliedNext()(scope const RuleData* data, Instant instant)
{
    const second = instant.getEpochSecond();
    const index = bound(data.wallEpochs, second);
    if (index < data.wallEpochs.length)
        return historicTransition(data, index);
    if (!data.annual.length)
        return Nullable!ZoneOffsetTransition.init;

    const year = transitionYear(second, data.wallOffsets[$ - 1]);
    ZoneOffsetTransition[maxRecurringRules] scratch;
    const annual = recurringIn(data, year, scratch[]);
    foreach (ref const transition; annual)
        if (second < transition.toEpochSecond())
            return Nullable!ZoneOffsetTransition(transition);
    if (year < LocalDate.MAX.getYear())
        return Nullable!ZoneOffsetTransition(recurringIn(data, year + 1, scratch[])[0]);
    return Nullable!ZoneOffsetTransition.init;
}

private Nullable!ZoneOffsetTransition suppliedPrevious()(scope const RuleData* data, Instant instant)
{
    auto second = instant.getEpochSecond();
    if (instant.getNano() && second < long.max)
        ++second;

    const lastHistoric = data.wallEpochs[$ - 1];
    if (data.annual.length && second > lastHistoric)
    {
        const finalOffset = data.wallOffsets[$ - 1];
        const year = transitionYear(second, finalOffset);
        ZoneOffsetTransition[maxRecurringRules] scratch;
        const annual = recurringIn(data, year, scratch[]);
        foreach_reverse (ref const transition; annual)
            if (second > transition.toEpochSecond())
                return Nullable!ZoneOffsetTransition(transition);
        if (year - 1 > transitionYear(lastHistoric, finalOffset))
            return Nullable!ZoneOffsetTransition(recurringIn(data, year - 1, scratch[])[$ - 1]);
    }
    const index = bound(data.wallEpochs, second, false);
    return index ? historicTransition(data, index - 1) : Nullable!ZoneOffsetTransition.init;
}

private Nullable!ZoneOffsetTransition historicTransition()(scope const RuleData* data, size_t index)
{
    const before = data.wallOffsets[index];
    const after = data.wallOffsets[index + 1];
    const date = LocalDateTime.ofEpochSecond(data.wallEpochs[index], 0, before);
    return Nullable!ZoneOffsetTransition(ZoneOffsetTransition(date, before, after));
}

private bool sameRules()(scope const RuleData* left, scope const RuleData* right) pure nothrow @nogc
{
    return left.standardEpochs == right.standardEpochs && left.standardOffsets == right.standardOffsets
        && left.wallEpochs == right.wallEpochs && left.wallOffsets == right.wallOffsets && left.annual == right.annual;
}

private ZoneOffsetTransition[] recurringIn()(scope const RuleData* data, int year,
        return scope ZoneOffsetTransition[] scratch)
{
    auto result = scratch[0 .. data.annual.length];
    foreach (i, ref const rule; data.annual)
        result[i] = rule.createTransition(year);
    return result;
}

// Find the first entry after the key, or the first at or after it for an exclusive previous lookup.
private size_t bound(T)(scope const(T)[] items, T value, bool afterEqual = true) pure nothrow @nogc
{
    size_t first;
    size_t end = items.length;
    while (first < end)
    {
        const middle = first + (end - first) / 2;
        static if (is(T == long))
            const order = items[middle] < value ? -1 : items[middle] > value ? 1 : 0;
        else
            const order = items[middle].compareTo(value);
        if (order < 0 || (order == 0 && afterEqual))
            first = middle + 1;
        else
            end = middle;
    }
    return first;
}

private int transitionYear(long second, ZoneOffset offset)
{
    enum secondsPerDay = 86_400;
    const remainder = second % secondsPerDay + offset.getTotalSeconds();
    const days = second / secondsPerDay + (remainder < 0 ? (remainder + 1) / secondsPerDay - 1 : remainder
            / secondsPerDay);
    if (days >= LocalDate.MAX.toEpochDay())
        return LocalDate.MAX.getYear();
    if (days <= LocalDate.MIN.toEpochDay())
        return LocalDate.MIN.getYear();
    return LocalDate.ofEpochDay(days).getYear();
}

private int arrayHash(T)(scope const(T)[] items) pure nothrow @nogc
{
    uint result = 1;
    foreach (ref const item; items)
    {
        static if (is(T == long))
            const value = cast(uint) item ^ cast(uint)(cast(ulong) item >> 32);
        else static if (is(T == ZoneOffset))
            const value = cast(uint) item.getTotalSeconds();
        else
            const value = cast(uint) item.hashCode();
        result = 31 * result + value;
    }
    return cast(int) result;
}
