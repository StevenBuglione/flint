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
 * lib/thymeleaf/src/main/java/org/thymeleaf/standard/inline/StandardInlineMode.java
 * Modified by the Flint authors.
 */
module flint.thymeleaf.standard.inline;

import flint.java.lang : IllegalArgumentException;

@safe:

/// Inlining modes available to Thymeleaf's standard dialect (R20).
enum StandardInlineMode
{
    NONE,
    HTML,
    XML,
    TEXT,
    JAVASCRIPT,
    CSS
}

// Keep in StandardInlineMode declaration order.
private immutable string[] modeNames = ["NONE", "HTML", "XML", "TEXT", "JAVASCRIPT", "CSS"];

/// Resolve the original mode string case-insensitively (R20).
/// Throws IllegalArgumentException for null, trim-empty, or unrecognized input.
StandardInlineMode parse(string mode)
{
    foreach (index, name; modeNames)
        if (matchesModeName(mode, name))
            return cast(StandardInlineMode) index;

    // Java trim only removes characters up to U+0020.
    foreach (unit; mode)
        if (unit > ' ')
            throw new IllegalArgumentException("Unrecognized inline mode: " ~ mode);

    throw new IllegalArgumentException("Inline mode cannot be null or empty");
}

private bool matchesModeName(scope const(char)[] input, string name) pure nothrow @nogc
{
    if (input.length < name.length || input.length > name.length * 2)
        return false;

    foreach (expected; name)
    {
        if (input.length == 0)
            return false;
        if (input[0] == expected || input[0] == expected + ('a' - 'A'))
        {
            input = input[1 .. $];
            continue;
        }
        if (input.length < 2)
            return false;

        const pair = (cast(uint) input[0] << 8) | input[1];
        // Java equalsIgnoreCase also matches U+0130/U+0131 to I and U+017F to S.
        if ((expected == 'I' && (pair == 0xc4b0 || pair == 0xc4b1)) || (expected == 'S' && pair == 0xc5bf))
            input = input[2 .. $];
        else
            return false;
    }
    return input.length == 0;
}
