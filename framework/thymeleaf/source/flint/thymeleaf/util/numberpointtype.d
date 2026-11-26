/*
 * Copyright (c) 2011-2026 Thymeleaf (http://www.thymeleaf.org)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Ported from thymeleaf 3.1.7.RELEASE:
 * lib/thymeleaf/src/main/java/org/thymeleaf/util/NumberPointType.java
 * Modified by the Flint authors.
 */
module flint.thymeleaf.util.numberpointtype;

import flint.java.lang : IllegalArgumentException, NullPointerException;

@safe:

/// The separator choices for Thymeleaf number formatting (R15).
struct NumberPointType
{
    private ubyte index;

    private this(ubyte index) pure nothrow @nogc
    {
        this.index = index;
    }

    /// Use a period.
    static immutable NumberPointType POINT = NumberPointType(0);
    /// Use a comma.
    static immutable NumberPointType COMMA = NumberPointType(1);
    /// Use a space.
    static immutable NumberPointType WHITESPACE = NumberPointType(2);
    /// Use no separator.
    static immutable NumberPointType NONE = NumberPointType(3);
    /// Use the locale's separator.
    static immutable NumberPointType DEFAULT = NumberPointType(4);

    private static immutable types = [POINT, COMMA, WHITESPACE, NONE, DEFAULT];
    private static immutable names = ["POINT", "COMMA", "WHITESPACE", "NONE", "DEFAULT"];

    /// Resolve the exact declared name, returning an absent value for null or unknown input (R5).
    static auto match()(string name) pure nothrow @nogc
    {
        import std.typecons : Nullable;

        const index = indexOf(name);
        return index < 0 ? Nullable!NumberPointType.init : Nullable!NumberPointType(types[index]);
    }

    /// The separator's declared name.
    string getName() const pure nothrow @nogc
    {
        return names[index];
    }

    /// The enum constant's name (R15).
    string name() const pure nothrow @nogc
    {
        return getName();
    }

    /// The enum constant's declaration order (R15).
    int ordinal() const pure nothrow @nogc
    {
        return index;
    }

    /// All constants in declaration order, in an independent array (R15).
    static NumberPointType[] values() pure
    {
        auto result = new NumberPointType[types.length];
        result[] = types[];
        return result;
    }

    /// Resolve the exact declared name or throw the corresponding Java exception (R15).
    static NumberPointType valueOf(string name)
    {
        if (name is null)
            throw new NullPointerException("Name is null");
        const index = indexOf(name);
        if (index < 0)
            throw new IllegalArgumentException("No enum constant org.thymeleaf.util.NumberPointType." ~ name);
        return types[index];
    }

    private static int indexOf(scope const(char)[] name) pure nothrow @nogc
    {
        foreach (index, candidate; names)
            if (name == candidate)
                return cast(int) index;
        return -1;
    }

    /// The separator's declared name.
    string toString() const pure nothrow @nogc
    {
        return getName();
    }
}
