/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/main/java/org/springframework/http/converter/FormHttpMessageConverter.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: the MockMvc form codec uses the charsets defined by Flint's Java façade.
+/
module flint.test.web.servlet.form;

import flint.engine.aot.text : decodeUtf8, isValidUtf8;
import flint.java.nio.charset : Charset, StandardCharsets;
import flint.util : Assert, LinkedMultiValueMap, MultiValueMap, StringUtils;
import flint.web.util : UriUtils;

@safe:

package(flint.test.web.servlet) const(ubyte)[] writeForm(MultiValueMap!(string, string) fields, Charset charset)
{
    char[] text;
    fields.forEach((name, values) {
        if (name is null)
        {
            Assert.isTrue(values.isEmpty(), () => "Null name in form data: " ~ fields.toString());
            return;
        }
        foreach (value; values.toArray())
        {
            if (text.length != 0)
                text ~= '&';
            encodeComponent(text, name, charset);
            if (value !is null)
            {
                text ~= '=';
                encodeComponent(text, value, charset);
            }
        }
    });
    return cast(const(ubyte)[]) encodeText(text.length == 0 ? "" : text.idup, charset);
}

package(flint.test.web.servlet) MultiValueMap!(string, string) readForm(const(ubyte)[] content, Charset charset)
{
    const text = decodeText(cast(string) content.idup, charset);
    auto fields = new LinkedMultiValueMap!(string, string);
    foreach (pair; StringUtils.tokenizeToStringArray(text, "&"))
    {
        size_t delimiter;
        while (delimiter < pair.length && pair[delimiter] != '=')
            ++delimiter;
        const name = decodeComponent(pair[0 .. delimiter], charset, true);
        const value = delimiter == pair.length ? null : decodeComponent(pair[delimiter + 1 .. $], charset, true);
        fields.add(name, value);
    }
    return fields;
}

package(flint.test.web.servlet) string decodeFormRequestParameter(string text) pure
{
    return decodeComponent(text, StandardCharsets.UTF_8, false);
}

private bool formSafe(char c) pure nothrow @nogc
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-'
        || c == '_' || c == '.' || c == '*';
}

private void encodeComponent(ref char[] result, string text, Charset charset) pure nothrow
{
    enum hex = "0123456789ABCDEF";
    size_t index;
    while (index < text.length)
    {
        const c = text[index];
        if (formSafe(c) || c == ' ')
        {
            result ~= c == ' ' ? '+' : c;
            ++index;
            continue;
        }
        const start = index++;
        while (index < text.length && !formSafe(text[index]) && text[index] != ' ')
            ++index;
        foreach (char octet; encodeText(text[start .. index], charset))
        {
            result ~= '%';
            result ~= hex[octet >> 4];
            result ~= hex[octet & 0x0F];
        }
    }
}

private string decodeComponent(string text, Charset charset, bool plusAsSpace) pure
{
    char[] result;
    size_t index;
    while (index < text.length)
    {
        const c = text[index];
        if (c != '%')
        {
            result ~= c == '+' && plusAsSpace ? ' ' : c;
            ++index;
            continue;
        }
        const start = index;
        do
        {
            index = text.length - index < 3 ? text.length : index + 3;
        }
        while (index < text.length && text[index] == '%');
        result ~= decodeText(UriUtils.decode(text[start .. index]), charset);
    }
    return result.length == 0 ? "" : result.idup;
}

private string encodeText(string text, Charset charset) pure nothrow
{
    if (text.length == 0 || charset == StandardCharsets.UTF_8)
        return text;

    char[] result;
    size_t index;
    if (charset == StandardCharsets.US_ASCII || charset == StandardCharsets.ISO_8859_1)
    {
        const limit = charset == StandardCharsets.US_ASCII ? 0x7F : 0xFF;
        while (index < text.length)
        {
            const codePoint = decodeUtf8(text, index);
            result ~= codePoint <= limit ? cast(char) codePoint : '?';
        }
        return result.idup;
    }

    const littleEndian = charset == StandardCharsets.UTF_16LE;
    if (charset == StandardCharsets.UTF_16)
        appendUnit(result, 0xFEFF, littleEndian);
    while (index < text.length)
    {
        const codePoint = decodeUtf8(text, index);
        if (codePoint <= 0xFFFF)
            appendUnit(result, cast(ushort) codePoint, littleEndian);
        else
        {
            const adjusted = codePoint - 0x10000;
            appendUnit(result, cast(ushort)(0xD800 + (adjusted >> 10)), littleEndian);
            appendUnit(result, cast(ushort)(0xDC00 + (adjusted & 0x03FF)), littleEndian);
        }
    }
    return result.idup;
}

private void appendUnit(ref char[] result, ushort value, bool littleEndian) pure nothrow
{
    const high = cast(char)(value >> 8);
    const low = cast(char) value;
    result ~= littleEndian ? low : high;
    result ~= littleEndian ? high : low;
}

private string decodeText(string text, Charset charset) pure nothrow
{
    if (text.length == 0)
        return text;

    char[] result;
    if (charset == StandardCharsets.UTF_8)
    {
        if (isValidUtf8(text))
            return text;
        size_t index;
        while (index < text.length)
        {
            const start = index;
            const codePoint = decodeUtf8(text, index);
            if (codePoint == 0xFFFD)
                index = start + utf8ReplacementWidth(text[start .. $]);
            result ~= codePoint;
        }
    }
    else if (charset == StandardCharsets.US_ASCII || charset == StandardCharsets.ISO_8859_1)
    {
        foreach (char octet; text)
            result ~= octet <= 0x7F || charset == StandardCharsets.ISO_8859_1 ? cast(dchar) octet : '\uFFFD';
    }
    else
        return decodeUtf16(text, charset);
    return result.idup;
}

// Java's UTF-8 decoder resumes at the first byte outside the malformed sequence.
private size_t utf8ReplacementWidth(scope const(char)[] text) pure nothrow @nogc
{
    const lead = text[0];
    if (lead < 0xC2 || lead > 0xF4 || text.length == 1)
        return 1;

    const second = text[1];
    if ((lead == 0xE0 && second < 0xA0) || (lead == 0xF0 && second < 0x90) || (lead == 0xF4 && second > 0x8F))
        return 1;

    const width = lead < 0xE0 ? 2 : lead < 0xF0 ? 3 : 4;
    size_t index = 1;
    while (index < width && index < text.length && (text[index] & 0xC0) == 0x80)
        ++index;
    return index;
}

private string decodeUtf16(string text, Charset charset) pure nothrow
{
    enum dchar replacement = 0xFFFD;
    bool littleEndian = charset == StandardCharsets.UTF_16LE;
    size_t index;
    if (charset == StandardCharsets.UTF_16 && text.length >= 2)
    {
        const marker = readUnit(text, 0, false);
        if (marker == 0xFEFF || marker == 0xFFFE)
        {
            littleEndian = marker == 0xFFFE;
            index = 2;
        }
    }
    char[] result;
    while (text.length - index >= 2)
    {
        const first = readUnit(text, index, littleEndian);
        index += 2;
        if (first < 0xD800 || first > 0xDFFF)
            result ~= cast(dchar) first;
        else if (first <= 0xDBFF)
        {
            if (text.length - index < 2)
            {
                result ~= replacement;
                index = text.length;
                break;
            }
            const second = readUnit(text, index, littleEndian);
            index += 2;
            if (second >= 0xDC00 && second <= 0xDFFF)
                result ~= cast(dchar)(0x10000 + ((first - 0xD800) << 10) + second - 0xDC00);
            else
                result ~= replacement;
        }
        else
            result ~= replacement;
    }
    if (index != text.length)
        result ~= replacement;
    return result.length == 0 ? "" : result.idup;
}

private ushort readUnit(string text, size_t index, bool littleEndian) pure nothrow @nogc
{
    const first = text[index];
    const second = text[index + 1];
    return cast(ushort)(littleEndian ? first | (second << 8) : (first << 8) | second);
}
