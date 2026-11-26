/*
 * =============================================================================
 *
 *   Copyright (c) 2011-2026 Thymeleaf (http://www.thymeleaf.org)
 *
 *   Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *   You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 *
 * =============================================================================
 *
 * Ported from thymeleaf 3.1.7.RELEASE:
 * lib/thymeleaf/src/main/java/org/thymeleaf/util/LoggingUtils.java
 * Modified by the Flint authors.
 */
module flint.thymeleaf.util.loggingutils;

import flint.engine.aot.text : decodeUtf8;
import std.typecons : Nullable;

@safe:

/// Formats a template name for use in Thymeleaf diagnostics.
final class LoggingUtils
{
    @disable this();

    /// Preserve null (R5) and limit long names to Java's 35 prefix and 80 suffix UTF-16 units (R14).
    static Nullable!string loggifyTemplateName(Nullable!string templateName) pure nothrow
    {
        if (templateName.isNull)
            return templateName;

        const text = templateName.get;
        size_t offset, units, prefixEnd;
        bool hasLineFeed, splitPrefix;
        while (offset < text.length && units <= 120)
        {
            const start = offset;
            const point = decodeUtf8(text, offset);
            const nextUnits = units + (point > 0xFFFF ? 2 : 1);
            if (units < 35 && nextUnits >= 35)
            {
                splitPrefix = nextUnits > 35;
                prefixEnd = splitPrefix ? start : offset;
            }
            hasLineFeed |= point == '\n';
            units = nextUnits;
        }

        if (units <= 120 && !hasLineFeed)
            return templateName;

        // The decoder advances at most four bytes per unit, even for malformed input.
        char[120 * 4] buffer;
        size_t length;
        if (units <= 120)
        {
            length = text.length;
            buffer[0 .. length] = text[];
        }
        else
        {
            const suffix = suffixWindow(text);
            // These slices fit in the same buffer, including the marker and any split UTF-16 halves.
            length = append(buffer[], length, text[0 .. prefixEnd]);
            if (splitPrefix)
                length = append(buffer[], length, "\uFFFD");
            length = append(buffer[], length, "[...]");
            if (suffix.split)
                length = append(buffer[], length, "\uFFFD");
            length = append(buffer[], length, text[suffix.start .. $]);
        }
        foreach (ref c; buffer[0 .. length])
            if (c == '\n')
                c = ' ';
        return Nullable!string(buffer[0 .. length].idup);
    }
}

private struct SuffixWindow
{
    size_t start;
    bool split;
}

private SuffixWindow suffixWindow(scope const(char)[] text) pure nothrow @nogc
{
    size_t end = text.length;
    size_t remaining = 80;
    while (remaining != 0 && end != 0)
    {
        size_t start = end - 1;
        while (start > 0 && end - start < 4 && (text[start] & 0xC0) == 0x80)
            --start;
        size_t offset = start;
        const point = decodeUtf8(text[0 .. end], offset);
        if (offset != end)
            start = end - 1;
        else if (point > 0xFFFF)
        {
            if (remaining == 1)
                return SuffixWindow(end, true);
            --remaining;
        }
        --remaining;
        end = start;
    }
    return SuffixWindow(end, false);
}

private size_t append(scope char[] output, size_t start, scope const(char)[] text) pure nothrow @nogc
{
    const end = start + text.length;
    output[start .. end] = text[];
    return end;
}
