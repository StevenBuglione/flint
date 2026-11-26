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
 * lib/thymeleaf/src/main/java/org/thymeleaf/templatemode/TemplateMode.java
 * Modified by the Flint authors.
 */
module flint.thymeleaf.templatemode;

import flint.java.lang : IllegalArgumentException, NullPointerException;

@safe:

/// Thymeleaf's template mode and its markup, text, and case-sensitivity classification (R15).
struct TemplateMode
{
    private ubyte index;

    private this(ubyte index) pure nothrow @nogc
    {
        this.index = index;
    }

    /// HTML markup.
    static immutable TemplateMode HTML = TemplateMode(0);
    /// XML markup.
    static immutable TemplateMode XML = TemplateMode(1);
    /// Plain text.
    static immutable TemplateMode TEXT = TemplateMode(2);
    /// JavaScript text.
    static immutable TemplateMode JAVASCRIPT = TemplateMode(3);
    /// CSS text.
    static immutable TemplateMode CSS = TemplateMode(4);
    /// Raw content.
    static immutable TemplateMode RAW = TemplateMode(5);

    private static immutable modes = [HTML, XML, TEXT, JAVASCRIPT, CSS, RAW];
    private static immutable names = ["HTML", "XML", "TEXT", "JAVASCRIPT", "CSS", "RAW"];

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

    /// All modes in declaration order, in a fresh array.
    static TemplateMode[] values() pure
    {
        return modes.dup;
    }

    /// Resolve the exact declared name.
    static TemplateMode valueOf(string name)
    {
        if (name is null)
            throw new NullPointerException("Name is null");
        foreach (ordinal, candidate; names)
            if (name == candidate)
                return modes[ordinal];
        throw new IllegalArgumentException("No enum constant org.thymeleaf.templatemode.TemplateMode." ~ name);
    }

    /// The declared name.
    string toString() const pure nothrow @nogc
    {
        return name();
    }

    /// Whether this is HTML or XML markup.
    bool isMarkup() const pure nothrow @nogc
    {
        return index <= XML.index;
    }

    /// Whether this is text, JavaScript, or CSS.
    bool isText() const pure nothrow @nogc
    {
        return index >= TEXT.index && index <= CSS.index;
    }

    /// Whether names in this mode are case-sensitive.
    bool isCaseSensitive() const pure nothrow @nogc
    {
        return index != HTML.index;
    }
}
