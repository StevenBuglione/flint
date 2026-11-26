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

// Ported from spring-ai v2.1.0, spring-ai-commons/src/main/java/org/springframework/ai/reader/{ExtractedTextFormatter,JsonMetadataGenerator}.java
// Modified by the Flint authors.
module flint.ai.reader;

import flint.engine.aot.any : Any;
import flint.java.lang : NullPointerException;
import flint.java.util : Map;
import flint.util : StringUtils;

@safe:

/// Formats extracted text before it is stored in a document.
final class ExtractedTextFormatter
{
    private Builder settings_;

    private this(Builder settings) pure nothrow @nogc
    {
        settings_ = settings;
    }

    /// Returns a new builder with the default settings.
    static Builder builder() pure nothrow @nogc
    {
        return Builder.init;
    }

    /// Creates a formatter with the default settings.
    static ExtractedTextFormatter defaults()
    {
        return builder().build();
    }

    /// Collapses adjacent blank lines, preserving a blank line at the end.
    static string trimAdjacentBlankLines(string pageText)
    {
        return collapseBlankLineRuns(normalizeSpaces(pageText, false), true);
    }

    /// Removes leading and trailing ASCII spaces and collapses interior runs.
    static string alignToLeft(string pageText)
    {
        return collapseBlankLineRuns(normalizeSpaces(pageText, true), false);
    }

    /// Removes bottom lines using the supplied separator. Empty separators count UTF-16 units (R14).
    static string deleteBottomTextLines(string pageText, int numberOfLines, string lineSeparator)
    {
        if (!StringUtils.hasText(pageText) || numberOfLines <= 0)
            return pageText;
        if (lineSeparator is null)
            throw new NullPointerException();
        if (lineSeparator.length == 0)
            return dropUtf16UnitsFromEnd(pageText, numberOfLines);
        if (lineSeparator.length > pageText.length)
            return pageText;

        size_t end = pageText.length;
        for (size_t index = pageText.length - lineSeparator.length + 1; index > 0 && numberOfLines > 0;
                )
        {
            --index;
            if (pageText[index .. index + lineSeparator.length] == lineSeparator)
            {
                end = index;
                --numberOfLines;
            }
        }
        return pageText[0 .. end];
    }

    /// Removes top lines using the supplied separator. Empty separators count UTF-16 units (R14).
    static string deleteTopTextLines(string pageText, int numberOfLines, string lineSeparator)
    {
        if (!StringUtils.hasText(pageText) || numberOfLines <= 0)
            return pageText;
        if (lineSeparator is null)
            throw new NullPointerException();
        if (lineSeparator.length > pageText.length)
            return pageText;
        if (lineSeparator.length == 0)
            return dropUtf16UnitsFromStart(pageText, numberOfLines);

        size_t start;
        const limit = pageText.length - lineSeparator.length;
        for (size_t index = 1; index <= limit && numberOfLines > 0; ++index)
        {
            if (pageText[index .. index + lineSeparator.length] == lineSeparator)
            {
                start = index;
                --numberOfLines;
            }
        }
        return pageText[start .. $];
    }

    /// Formats the first page.
    string format(string pageText)
    {
        return format(pageText, 0);
    }

    /// Formats the text, applying line deletion only after the skipped pages.
    string format(string pageText, int pageNumber)
    {
        auto text = trimAdjacentBlankLines(pageText);
        if (pageNumber >= settings_.skipPages_)
        {
            text = deleteTopTextLines(text, settings_.topLines_, settings_.separator_);
            text = deleteBottomTextLines(text, settings_.bottomLines_, settings_.separator_);
        }
        return settings_.leftAlignment_ ? alignToLeft(text) : text;
    }

    /// Configures the transformation applied to each page.
    static struct Builder
    {
        private bool leftAlignment_;
        private int skipPages_;
        private int topLines_;
        private int bottomLines_;
        version (Windows)
            private string separator_ = "\r\n";
        else
            private string separator_ = "\n";

        /// Enables or disables left alignment.
        ref Builder withLeftAlignment(bool enabled) return pure nothrow @nogc
        {
            leftAlignment_ = enabled;
            return this;
        }

        /// Skips line deletion on the given number of pages.
        ref Builder withNumberOfTopPagesToSkipBeforeDelete(int pages) return pure nothrow @nogc
        {
            skipPages_ = pages;
            return this;
        }

        /// Sets the number of top lines to delete.
        ref Builder withNumberOfTopTextLinesToDelete(int lines) return pure nothrow @nogc
        {
            topLines_ = lines;
            return this;
        }

        /// Sets the number of bottom lines to delete.
        ref Builder withNumberOfBottomTextLinesToDelete(int lines) return pure nothrow @nogc
        {
            bottomLines_ = lines;
            return this;
        }

        /// Overrides the platform line separator used to delete lines.
        ref Builder overrideLineSeparator(string separator) return pure nothrow @nogc
        {
            separator_ = separator;
            return this;
        }

        /// Creates a formatter with a copy of these settings.
        ExtractedTextFormatter build() const
        {
            return new ExtractedTextFormatter(this);
        }
    }
}

// The private replacements use Java's multiline regex boundaries, even though the
// following blank-line collapse treats only CR and LF as terminators.
private string normalizeSpaces(string text, bool leftAlign)
{
    if (text is null)
        throw new NullPointerException();
    string result = "";
    size_t start;
    while (start < text.length)
    {
        size_t end = start;
        size_t separatorWidth;
        while (end < text.length && (separatorWidth = multilineSeparatorWidth(text, end)) == 0)
            ++end;

        const line = text[start .. end];
        const firstWord = skipSpaces(line, 0);
        if (leftAlign)
            appendAligned(result, line, firstWord);
        else if (firstWord < line.length || separatorWidth != 1 || text[end] != '\n')
            result ~= line;
        start = end + separatorWidth;
        result ~= text[end .. start];
    }
    return result;
}

private void appendAligned(ref string result, scope const(char)[] line, size_t index)
{
    while (index < line.length)
    {
        const start = index;
        while (index < line.length && line[index] != ' ')
            ++index;
        result ~= line[start .. index];
        index = skipSpaces(line, index);
        if (index < line.length)
            result ~= ' ';
    }
}

private size_t skipSpaces(scope const(char)[] text, size_t index) pure nothrow @nogc
{
    while (index < text.length && text[index] == ' ')
        ++index;
    return index;
}

private size_t multilineSeparatorWidth(scope const(char)[] text, size_t index) pure nothrow @nogc
{
    const byte_ = cast(ubyte) text[index];
    if (byte_ == '\r')
        return crlfWidth(text, index);
    if (byte_ == '\n')
        return 1;
    if (byte_ == 0xc2 && text.length - index >= 2 && cast(ubyte) text[index + 1] == 0x85)
        return 2; // NEL
    if (byte_ == 0xe2 && text.length - index >= 3 && cast(ubyte) text[index + 1] == 0x80
            && (cast(ubyte) text[index + 2] == 0xa8 || cast(ubyte) text[index + 2] == 0xa9))
        return 3; // Unicode line or paragraph separator
    return 0;
}

private size_t crlfWidth(scope const(char)[] text, size_t index) pure nothrow @nogc
{
    return index + 1 < text.length && text[index + 1] == '\n' ? 2 : 1;
}

private string collapseBlankLineRuns(string text, bool keepFirst)
{
    string result = "";
    bool previousBlank;
    size_t start;
    while (start < text.length)
    {
        size_t terminator = start;
        while (terminator < text.length && text[terminator] != '\n' && text[terminator] != '\r')
            ++terminator;
        size_t end = terminator;
        if (terminator < text.length)
            end += text[terminator] == '\r' ? crlfWidth(text, terminator) : 1;

        const blank = terminator == start;
        if (!blank || end == text.length || (keepFirst && !previousBlank))
            result ~= text[start .. end];
        previousBlank = blank;
        start = end;
    }
    return result;
}

// An empty separator advances by UTF-16 units. A split surrogate becomes U+FFFD (R14).
private string dropUtf16UnitsFromStart(string text, int count)
{
    size_t index;
    while (index < text.length && count > 0)
    {
        const supplementary = cast(ubyte) text[index] >= 0xf0;
        ++index;
        while (index < text.length && isContinuation(text[index]))
            ++index;
        if (supplementary && count == 1)
            return "\uFFFD" ~ text[index .. $];
        count -= supplementary ? 2 : 1;
    }
    return text[index .. $];
}

private string dropUtf16UnitsFromEnd(string text, int count)
{
    size_t index = text.length;
    while (index > 0 && count > 0)
    {
        --index;
        while (index > 0 && isContinuation(text[index]))
            --index;
        const supplementary = cast(ubyte) text[index] >= 0xf0;
        if (supplementary && count == 1)
            return text[0 .. index] ~ "\uFFFD";
        count -= supplementary ? 2 : 1;
    }
    return text[0 .. index];
}

private bool isContinuation(char byte_) pure nothrow @nogc
{
    return (cast(ubyte) byte_ & 0xc0) == 0x80;
}

private alias JsonFields = Map!(string, Any);

/// Extracts metadata from the fields of a JSON document.
interface JsonMetadataGenerator
{
    /// Returns the fields to use as document metadata.
    JsonFields generate(JsonFields jsonMap);
}
