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
module flint.java.time.zone.zonerules;

import flint.java.lang : NullPointerException;
import flint.java.time : Duration, Instant, LocalDateTime, ZoneOffset;
import flint.java.time.zone.internal.rulestorage : LocalMatch, RuleStorage;
import flint.java.time.zone.zoneoffsettransition : ZoneOffsetTransition;
import flint.java.time.zone.zoneoffsettransitionrule : ZoneOffsetTransitionRule;
import flint.java.util : List;
import std.typecons : Nullable;

@safe:

/// Rules created from a fixed offset or snapshots of supplied transitions. The default represents UTC.
struct ZoneRules
{
    private ZoneOffset offset_;
    private immutable RuleStorage data_;

    private this(ZoneOffset offset, immutable RuleStorage data = null) pure nothrow @nogc
    {
        offset_ = offset;
        data_ = data;
    }

    static ZoneRules of(ZoneOffset offset) pure nothrow @nogc
    {
        return ZoneRules(offset);
    }

    static ZoneRules of()(Nullable!ZoneOffset offset) pure
    {
        if (offset.isNull)
            throw new NullPointerException("offset");
        return of(offset.get());
    }

    /// The transition lists are in chronological order and copied during construction.
    static ZoneRules of()(ZoneOffset baseStandardOffset, ZoneOffset baseWallOffset,
            List!ZoneOffsetTransition standardTransitions,
            List!ZoneOffsetTransition transitions, List!ZoneOffsetTransitionRule lastRules)
    {
        import flint.java.time.zone.internal.suppliedrules : makeSuppliedRules;

        return ZoneRules(baseWallOffset, makeSuppliedRules(baseStandardOffset, baseWallOffset,
                standardTransitions, transitions, lastRules));
    }

    static ZoneRules of()(Nullable!ZoneOffset baseStandardOffset, Nullable!ZoneOffset baseWallOffset,
            List!ZoneOffsetTransition standardTransitions,
            List!ZoneOffsetTransition transitions, List!ZoneOffsetTransitionRule lastRules)
    {
        if (baseStandardOffset.isNull)
            throw new NullPointerException("baseStandardOffset");
        if (baseWallOffset.isNull)
            throw new NullPointerException("baseWallOffset");
        return of(baseStandardOffset.get(), baseWallOffset.get(), standardTransitions, transitions, lastRules);
    }

    bool isFixedOffset() const pure nothrow @nogc
    {
        return data_ is null;
    }

    ZoneOffset getOffset(Instant instant) const
    {
        return hasWallChanges() ? data_.offsetAt(instant) : offset_;
    }

    ZoneOffset getOffset(LocalDateTime dateTime) const
    {
        return localMatch(dateTime).offset;
    }

    ZoneOffset getOffset()(Nullable!Instant instant) const
    {
        return getOffset(dateOrDefault(instant, hasWallChanges()));
    }

    ZoneOffset getOffset()(Nullable!LocalDateTime dateTime) const
    {
        return getOffset(dateOrDefault(dateTime, hasWallChanges()));
    }

    auto getValidOffsets()(LocalDateTime dateTime) const
    {
        import flint.java.util : Collections;

        const match = localMatch(dateTime);
        if (!match.transitioning)
            return Collections.singletonList!ZoneOffset(match.offset);
        if (match.after.getTotalSeconds() > match.offset.getTotalSeconds())
            return Collections.emptyList!ZoneOffset();
        return List!ZoneOffset.of(match.offset, match.after);
    }

    auto getValidOffsets()(Nullable!LocalDateTime dateTime) const
    {
        return getValidOffsets(dateOrDefault(dateTime, hasWallChanges()));
    }

    auto getTransition()(LocalDateTime dateTime) const
    {
        return asTransition(localMatch(dateTime));
    }

    auto getTransition()(Nullable!LocalDateTime dateTime) const
    {
        return getTransition(dateOrDefault(dateTime, hasWallChanges()));
    }

    ZoneOffset getStandardOffset(Instant instant) const pure nothrow @nogc
    {
        if (data_ is null)
            return offset_;
        return data_.standardAt(instant);
    }

    ZoneOffset getStandardOffset()(Nullable!Instant instant) const pure
    {
        return getStandardOffset(dateOrDefault(instant, hasStandardChanges()));
    }

    Duration getDaylightSavings(Instant instant) const
    {
        const seconds = getOffset(instant).getTotalSeconds() - getStandardOffset(instant).getTotalSeconds();
        return Duration.ofSeconds(seconds);
    }

    Duration getDaylightSavings()(Nullable!Instant instant) const
    {
        return getDaylightSavings(dateOrDefault(instant, hasWallChanges() || hasStandardChanges()));
    }

    bool isDaylightSavings(Instant instant) const
    {
        return getOffset(instant) != getStandardOffset(instant);
    }

    bool isDaylightSavings()(Nullable!Instant instant) const
    {
        return isDaylightSavings(dateOrDefault(instant, hasWallChanges() || hasStandardChanges()));
    }

    bool isValidOffset(LocalDateTime dateTime, ZoneOffset offset) const
    {
        const match = localMatch(dateTime);
        return validOffset(match, offset);
    }

    bool isValidOffset()(Nullable!LocalDateTime dateTime, ZoneOffset offset) const
    {
        return isValidOffset(dateOrDefault(dateTime, hasWallChanges()), offset);
    }

    bool isValidOffset()(LocalDateTime dateTime, Nullable!ZoneOffset offset) const
    {
        const match = localMatch(dateTime);
        if (offset.isNull)
            return false;
        return validOffset(match, offset.get());
    }

    bool isValidOffset()(Nullable!LocalDateTime dateTime, Nullable!ZoneOffset offset) const
    {
        return isValidOffset(dateOrDefault(dateTime, hasWallChanges()), offset);
    }

    auto nextTransition()(Instant instant) const
    {
        return hasWallChanges() ? asTransition(data_.next(instant)) : Nullable!ZoneOffsetTransition.init;
    }

    auto nextTransition()(Nullable!Instant instant) const
    {
        return nextTransition(dateOrDefault(instant, hasWallChanges()));
    }

    auto previousTransition()(Instant instant) const
    {
        return hasWallChanges() ? asTransition(data_.previous(instant)) : Nullable!ZoneOffsetTransition.init;
    }

    auto previousTransition()(Nullable!Instant instant) const
    {
        return previousTransition(dateOrDefault(instant, hasWallChanges()));
    }

    auto getTransitions()() const
    {
        import flint.java.util : Collections;

        if (!hasWallChanges())
            return Collections.emptyList!ZoneOffsetTransition();
        auto result = new ZoneOffsetTransition[data_.historicCount()];
        foreach (i, ref item; result)
            item = asTransition(data_.historic(i)).get();
        return List!ZoneOffsetTransition.of(result);
    }

    auto getTransitionRules()() const
    {
        import flint.java.util : Collections;

        if (data_ is null || !data_.annual().length)
            return Collections.emptyList!ZoneOffsetTransitionRule();
        return List!ZoneOffsetTransitionRule.of(data_.annual().dup);
    }

    bool equals(ZoneRules other) const pure nothrow @nogc
    {
        if (data_ is other.data_)
            return offset_ == other.offset_;
        return data_ !is null && other.data_ !is null && data_.same(other.data_);
    }

    bool opEquals(ZoneRules other) const pure nothrow @nogc
    {
        return equals(other);
    }

    int hashCode() const pure nothrow @nogc
    {
        // Fixed rules XOR three empty-array hashes and two identical singleton hashes.
        return data_ is null ? 1 : data_.hash();
    }

    size_t toHash() const pure nothrow @nogc
    {
        return cast(uint) hashCode();
    }

    string toString() const pure nothrow
    {
        enum prefix = "ZoneRules[currentStandardOffset=";
        const standard = data_ is null ? offset_ : data_.finalStandard();
        const id = standard.getId();
        auto text = new char[prefix.length + id.length + 1];
        text[0 .. prefix.length] = prefix[];
        text[prefix.length .. $ - 1] = id;
        text[$ - 1] = ']';
        return text;
    }

    private bool hasStandardChanges() const pure nothrow @nogc
    {
        return data_ !is null && data_.hasStandardChanges();
    }

    private bool hasWallChanges() const pure nothrow @nogc
    {
        return data_ !is null && data_.hasWallChanges();
    }

    private LocalMatch localMatch(LocalDateTime dateTime) const
    {
        return hasWallChanges() ? data_.localAt(dateTime) : LocalMatch(offset_);
    }

}

private bool validOffset(LocalMatch match, ZoneOffset candidate) pure nothrow @nogc
{
    if (!match.transitioning)
        return candidate == match.offset;
    return match.after.getTotalSeconds() <= match.offset.getTotalSeconds()
        && (candidate == match.offset || candidate == match.after);
}

private T dateOrDefault(T)(Nullable!T date, bool readsDate) pure
{
    if (!date.isNull)
        return date.get();
    if (readsDate)
        throw new NullPointerException();
    return T.init;
}

private Nullable!ZoneOffsetTransition asTransition()(LocalMatch match) pure nothrow @nogc
{
    if (!match.transitioning)
        return Nullable!ZoneOffsetTransition.init;
    return Nullable!ZoneOffsetTransition(ZoneOffsetTransition(match.beforeTime, match.offset, match.after));
}
