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
import std.typecons : Nullable;

@safe:

/// Time-zone rules created from one fixed offset. The default represents UTC.
struct ZoneRules
{
    private ZoneOffset offset_;

    private this(ZoneOffset offset) pure nothrow @nogc
    {
        offset_ = offset;
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

    bool isFixedOffset() const pure nothrow @nogc
    {
        return true;
    }

    ZoneOffset getOffset(Instant instant) const pure nothrow @nogc
    {
        return offset_;
    }

    ZoneOffset getOffset(LocalDateTime dateTime) const pure nothrow @nogc
    {
        return offset_;
    }

    ZoneOffset getOffset()(Nullable!Instant instant) const pure nothrow @nogc
    {
        return offset_;
    }

    ZoneOffset getOffset()(Nullable!LocalDateTime dateTime) const pure nothrow @nogc
    {
        return offset_;
    }

    auto getValidOffsets()(LocalDateTime dateTime) const
    {
        import flint.java.util : Collections;

        return Collections.singletonList!ZoneOffset(offset_);
    }

    auto getValidOffsets()(Nullable!LocalDateTime dateTime) const
    {
        return getValidOffsets(LocalDateTime.init);
    }

    auto getTransition()(LocalDateTime dateTime) const pure nothrow @nogc
    {
        return absentTransition();
    }

    auto getTransition()(Nullable!LocalDateTime dateTime) const pure nothrow @nogc
    {
        return absentTransition();
    }

    ZoneOffset getStandardOffset(Instant instant) const pure nothrow @nogc
    {
        return offset_;
    }

    ZoneOffset getStandardOffset()(Nullable!Instant instant) const pure nothrow @nogc
    {
        return offset_;
    }

    Duration getDaylightSavings(Instant instant) const pure nothrow @nogc
    {
        return Duration.ZERO;
    }

    Duration getDaylightSavings()(Nullable!Instant instant) const pure nothrow @nogc
    {
        return Duration.ZERO;
    }

    bool isDaylightSavings(Instant instant) const pure nothrow @nogc
    {
        return false;
    }

    bool isDaylightSavings()(Nullable!Instant instant) const pure nothrow @nogc
    {
        return false;
    }

    bool isValidOffset(LocalDateTime dateTime, ZoneOffset offset) const pure nothrow @nogc
    {
        return offset_ == offset;
    }

    bool isValidOffset()(Nullable!LocalDateTime dateTime, ZoneOffset offset) const pure nothrow @nogc
    {
        return offset_ == offset;
    }

    bool isValidOffset()(LocalDateTime dateTime, Nullable!ZoneOffset offset) const pure nothrow @nogc
    {
        return !offset.isNull && offset_ == offset.get();
    }

    bool isValidOffset()(Nullable!LocalDateTime dateTime, Nullable!ZoneOffset offset) const pure nothrow @nogc
    {
        return isValidOffset(LocalDateTime.init, offset);
    }

    auto nextTransition()(Instant instant) const pure nothrow @nogc
    {
        return absentTransition();
    }

    auto nextTransition()(Nullable!Instant instant) const pure nothrow @nogc
    {
        return absentTransition();
    }

    auto previousTransition()(Instant instant) const pure nothrow @nogc
    {
        return absentTransition();
    }

    auto previousTransition()(Nullable!Instant instant) const pure nothrow @nogc
    {
        return absentTransition();
    }

    auto getTransitions()() const
    {
        import flint.java.time.zone.zoneoffsettransition : ZoneOffsetTransition;
        import flint.java.util : Collections;

        return Collections.emptyList!ZoneOffsetTransition();
    }

    auto getTransitionRules()() const
    {
        import flint.java.time.zone.zoneoffsettransitionrule : ZoneOffsetTransitionRule;
        import flint.java.util : Collections;

        return Collections.emptyList!ZoneOffsetTransitionRule();
    }

    bool equals(ZoneRules other) const pure nothrow @nogc
    {
        return offset_ == other.offset_;
    }

    int hashCode() const pure nothrow @nogc
    {
        // Java XORs three empty-array hashes and two identical singleton-offset hashes.
        return 1;
    }

    string toString() const pure nothrow
    {
        enum prefix = "ZoneRules[currentStandardOffset=";
        const id = offset_.getId();
        auto text = new char[prefix.length + id.length + 1];
        text[0 .. prefix.length] = prefix[];
        text[prefix.length .. $ - 1] = id;
        text[$ - 1] = ']';
        return text;
    }

    // Instantiate the transition type only in callers that query transitions.
    private static auto absentTransition()() pure nothrow @nogc
    {
        import flint.java.time.zone.zoneoffsettransition : ZoneOffsetTransition;

        return Nullable!ZoneOffsetTransition.init;
    }
}
