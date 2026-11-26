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
 * lib/thymeleaf/src/main/java/org/thymeleaf/engine/HTMLElementType.java
 * lib/thymeleaf/src/main/java/org/thymeleaf/engine/IThrottledTemplateWriterControl.java
 * Modified by the Flint authors.
 */
module flint.thymeleaf.engine;

import flint.java.lang : IllegalArgumentException, NullPointerException;

@safe:

/// Thymeleaf's HTML element classification (R15).
struct HTMLElementType
{
    private ubyte index;

    private this(ubyte index) pure nothrow @nogc
    {
        this.index = index;
    }

    /// A void element.
    static immutable HTMLElementType VOID = HTMLElementType(0);
    /// A raw text element.
    static immutable HTMLElementType RAW_TEXT = HTMLElementType(1);
    /// An escapable raw text element.
    static immutable HTMLElementType ESCAPABLE_RAW_TEXT = HTMLElementType(2);
    /// An element in a foreign namespace.
    static immutable HTMLElementType FOREIGN = HTMLElementType(3);
    /// A normal HTML element.
    static immutable HTMLElementType NORMAL = HTMLElementType(4);

    private static immutable names = ["VOID", "RAW_TEXT", "ESCAPABLE_RAW_TEXT", "FOREIGN", "NORMAL"];

    /// The declared name.
    string name() const pure nothrow @nogc
    {
        return names[index];
    }

    /// The declaration order.
    int ordinal() const pure nothrow @nogc
    {
        return index;
    }

    /// All element types in declaration order, in a fresh array.
    static HTMLElementType[] values() pure
    {
        return [VOID, RAW_TEXT, ESCAPABLE_RAW_TEXT, FOREIGN, NORMAL];
    }

    /// Resolve the exact declared name.
    static HTMLElementType valueOf(string name)
    {
        if (name is null)
            throw new NullPointerException("Name is null");
        foreach (index, candidate; names)
            if (name == candidate)
                return HTMLElementType(cast(ubyte) index);
        throw new IllegalArgumentException("No enum constant org.thymeleaf.engine.HTMLElementType." ~ name);
    }

    /// The declared name.
    string toString() const pure nothrow @nogc
    {
        return name();
    }

    /// Whether this is a void element.
    bool isVoid() const pure nothrow @nogc
    {
        return index == VOID.index;
    }
}

/// Status reported by the writer during a throttled template execution.
interface IThrottledTemplateWriterControl
{
    /// Whether the writer has pending overflow.
    /// Throws IOException if the writer cannot report its state (D-8).
    bool isOverflown();

    /// Whether the writer has stopped producing output.
    /// Throws IOException if the writer cannot report its state (D-8).
    bool isStopped();

    /// The output count reported by the writer.
    int getWrittenCount();

    /// The writer's peak overflow buffer size.
    int getMaxOverflowSize();

    /// The number of overflow buffer growth operations.
    int getOverflowGrowCount();
}
