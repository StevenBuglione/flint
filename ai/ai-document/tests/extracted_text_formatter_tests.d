/*
 * Copyright 2023-present the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Ported from spring-ai v2.1.0, spring-ai-commons/src/test/java/org/springframework/ai/reader/ExtractedTextFormatterTests.java
// Modified by the Flint authors.
module extracted_text_formatter_tests;

import flint.ai.reader : ExtractedTextFormatter;
import flint.java.lang : NullPointerException;
import std.exception : assertThrown;

@safe:

private alias Formatter = ExtractedTextFormatter;

private struct BlankLineCase
{
    string input;
    string trimmed;
    string aligned;
}

private immutable BlankLineCase[] blankLineCases = [
    BlankLineCase("a\n\n\nb", "a\n\nb", "a\nb"), BlankLineCase("a\n\nb", "a\n\nb", "a\nb"),
    BlankLineCase("a\nb", "a\nb", "a\nb"), BlankLineCase("a\n \n\nb", "a\n\nb", "a\nb"),
    BlankLineCase("\n\na", "\na", "a"), BlankLineCase("a\n\n", "a\n\n", "a\n\n"),
    BlankLineCase("a\n\n\r\n\nb", "a\n\nb", "a\nb"),
    BlankLineCase("a\r\n\r\n\r\nb", "a\r\n\r\nb", "a\r\nb"),
    BlankLineCase("a\n\nb\n\nc", "a\n\nb\n\nc", "a\nb\nc"), BlankLineCase("", "", ""),
    BlankLineCase("a", "a", "a"), BlankLineCase("a\n", "a\n", "a\n"),
];

@("trimAdjacentBlankLinesMatchesPreviousBehavior")
unittest
{
    foreach (ref sample; blankLineCases)
        assert(Formatter.trimAdjacentBlankLines(sample.input) == sample.trimmed);
}

@("alignToLeftMatchesPreviousBehavior")
unittest
{
    foreach (ref sample; blankLineCases)
        assert(Formatter.alignToLeft(sample.input) == sample.aligned);
}

@("formatWithLeftAlignmentMatchesPreviousBehavior")
unittest
{
    auto formatter = Formatter.builder().withLeftAlignment(true).build();
    foreach (ref sample; blankLineCases)
    {
        const expected = Formatter.alignToLeft(Formatter.trimAdjacentBlankLines(sample.input));
        assert(formatter.format(sample.input) == expected);
    }
}

@("formatWithoutLeftAlignmentMatchesPreviousBehavior")
unittest
{
    auto formatter = Formatter.builder().withLeftAlignment(false).build();
    foreach (ref sample; blankLineCases)
        assert(formatter.format(sample.input) == sample.trimmed);
}

@("largeRunsOfBlankLinesDoNotFailAndStillCollapse")
unittest
{
    foreach (blankLineCount; [50_000, 200_000])
    {
        auto raw = new char[blankLineCount + 3];
        raw[] = '\n';
        raw[0] = 'a';
        raw[$ - 1] = 'b';
        const input = raw.idup;
        assert(Formatter.trimAdjacentBlankLines(input) == "a\n\nb");
        assert(Formatter.alignToLeft(input) == "a\nb");
    }
}

@("Java multiline boundaries preserve Unicode separators and tab content")
unittest
{
    assert(Formatter.alignToLeft("  a   b  \t\t   c  ") == "a b \t\t c");
    assert(Formatter.trimAdjacentBlankLines("a\r \n\r\nb") == "a\r\n\r\nb");
    assert(Formatter.alignToLeft("a\r \n\r\nb") == "a\r\nb");
    assert(Formatter.alignToLeft("  α  \u0085  😀  \u2028  β  \u2029  ") == "α\u0085😀\u2028β\u2029");
    assert(Formatter.trimAdjacentBlankLines("a\u0085 \n\nb") == "a\u0085\n\nb");
    assert(Formatter.trimAdjacentBlankLines("a\u2028 \u2029\n\nb") == "a\u2028 \u2029\n\nb");
    assert(Formatter.alignToLeft("a\u2028 \u2029\n\nb") == "a\u2028\u2029\nb");
    assert(Formatter.alignToLeft("  \r\n \n") == "\n");
}

@("line deletion keeps Java offsets and builder settings")
unittest
{
    const input = "heading| middle |footer";
    auto builder = Formatter.builder().withNumberOfTopPagesToSkipBeforeDelete(2).withNumberOfTopTextLinesToDelete(1)
        .withNumberOfBottomTextLinesToDelete(1).overrideLineSeparator("|").withLeftAlignment(true);
    auto formatter = builder.build();
    builder.withNumberOfTopTextLinesToDelete(2);
    assert(formatter.format(input, 1) == input);
    assert(formatter.format(input, 2) == "| middle");
    assert(Formatter.defaults().format("  plain  ") == "  plain  ");
    assert(Formatter.deleteTopTextLines("|middle|footer", 1, "|") == "|footer");
    assert(Formatter.deleteTopTextLines(input, 20, "|") == "|footer");
    assert(Formatter.deleteBottomTextLines(input, 20, "|") == "heading");
    assert(Formatter.deleteTopTextLines("Ω😀", 1, "") == "😀");
    assert(Formatter.deleteTopTextLines("Ω😀", 2, "") == "\uFFFD");
    assert(Formatter.deleteBottomTextLines("Ω😀", 1, "") == "Ω\uFFFD");
    assert(Formatter.deleteBottomTextLines("Ω😀", 2, "") == "Ω");
}

@("null and whitespace follow Java exception and passthrough rules")
unittest
{
    assertThrown!NullPointerException(Formatter.alignToLeft(null));
    assertThrown!NullPointerException(Formatter.trimAdjacentBlankLines(null));
    assertThrown!NullPointerException(Formatter.deleteTopTextLines("page", 1, null));
    assertThrown!NullPointerException(Formatter.deleteBottomTextLines("page", 1, null));
    assert(Formatter.deleteTopTextLines(null, 1, null) is null);
    assert(Formatter.deleteBottomTextLines("\u2003\t", 1, null) == "\u2003\t");
    assert(Formatter.deleteTopTextLines("page", 0, null) == "page");
}
