/*
 * Copyright (c) 2012, 2023, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/time/zone/ZoneOffsetTransition.java
// Modified by the Flint authors.
module flint.java.time.zone.zoneoffsettransition;

import flint.java.lang : IllegalArgumentException;
import flint.java.time : Duration, Instant, LocalDateTime, ZoneOffset;
import std.typecons : Nullable;

@safe:

/// A discontinuity between two offsets. The default value is a one-hour gap at the Unix epoch.
struct ZoneOffsetTransition
{
    private LocalDateTime beforeTime_;
    private ZoneOffset before_;
    private ZoneOffset after_ = ZoneOffset.ofHours(1);

    // Recurring rules can produce a transition whose offsets are equal.
    package(flint.java.time.zone) this(LocalDateTime transition, ZoneOffset before, ZoneOffset after) pure nothrow @nogc
    {
        beforeTime_ = transition;
        before_ = before;
        after_ = after;
    }

    /// The local time at which the before offset ceases to apply.
    static ZoneOffsetTransition of(LocalDateTime transition, ZoneOffset offsetBefore, ZoneOffset offsetAfter) pure
    {
        if (offsetBefore == offsetAfter)
            throw new IllegalArgumentException("Offsets must not be equal");
        if (transition.getNano() != 0)
            throw new IllegalArgumentException("Nano-of-second must be zero");
        return ZoneOffsetTransition(transition, offsetBefore, offsetAfter);
    }

    Instant getInstant() const pure nothrow @nogc
    {
        return Instant.ofEpochSecond(toEpochSecond());
    }

    long toEpochSecond() const pure nothrow @nogc
    {
        return beforeTime_.toEpochSecond(before_);
    }

    LocalDateTime getDateTimeBefore() const pure nothrow @nogc
    {
        return beforeTime_;
    }

    LocalDateTime getDateTimeAfter() const
    {
        return beforeTime_.plusSeconds(offsetChange());
    }

    ZoneOffset getOffsetBefore() const pure nothrow @nogc
    {
        return before_;
    }

    ZoneOffset getOffsetAfter() const pure nothrow @nogc
    {
        return after_;
    }

    Duration getDuration() const pure nothrow @nogc
    {
        return Duration.ofSeconds(offsetChange());
    }

    bool isGap() const pure nothrow @nogc
    {
        return offsetChange() > 0;
    }

    bool isOverlap() const pure nothrow @nogc
    {
        return offsetChange() < 0;
    }

    bool isValidOffset(ZoneOffset offset) const pure nothrow @nogc
    {
        return !isGap() && (offset == before_ || offset == after_);
    }

    // Instantiate the nullable adapter in its caller so it does not couple archive members.
    bool isValidOffset()(Nullable!ZoneOffset offset) const pure nothrow @nogc
    {
        return !offset.isNull && isValidOffset(offset.get());
    }

    /// Order transitions by instant. Equality also compares the local time and both offsets.
    int compareTo(ZoneOffsetTransition other) const pure nothrow @nogc
    {
        const instant = toEpochSecond(), otherInstant = other.toEpochSecond();
        return instant < otherInstant ? -1 : instant > otherInstant ? 1 : 0;
    }

    bool equals(ZoneOffsetTransition other) const pure nothrow @nogc
    {
        return beforeTime_ == other.beforeTime_ && before_ == other.before_ && after_ == other.after_;
    }

    int hashCode() const pure nothrow @nogc
    {
        const after = cast(uint) after_.getTotalSeconds();
        return beforeTime_.hashCode() ^ before_.getTotalSeconds() ^ cast(int)((after << 16) | (after >> 16));
    }

    string toString() const pure nothrow
    {
        const prefix = isGap() ? "Transition[Gap at " : "Transition[Overlap at ";
        const string[6] parts = [
            prefix, beforeTime_.toString(), before_.getId(), " to ", after_.getId(), "]"
        ];
        size_t size;
        foreach (part; parts)
            size += part.length;
        auto result = new char[size];
        size_t position;
        foreach (part; parts)
        {
            result[position .. position + part.length] = part[];
            position += part.length;
        }
        return result;
    }

    private int offsetChange() const pure nothrow @nogc
    {
        return after_.getTotalSeconds() - before_.getTotalSeconds();
    }
}
