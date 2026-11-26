/*
 * Copyright 2002-present the original author or authors.
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
 *
 * Ported from spring-framework v7.1.0:
 * spring-expression/src/main/java/org/springframework/expression/spel/standard/Tokenizer.java
 * Also from ast/Literal.java and ast/StringLiteral.java.
 * Modified by the Flint authors.
 */
module flint.expression.spel.standard.literal;

import flint.engine.aot.any : Any;
import flint.engine.aot.text : ParsedLong, decodeUtf8, tryParseDouble, tryParseFloat, tryParseLong;
import flint.expression.spel : SpelMessage, SpelParseException;
import std.ascii : isAlpha, isDigit, isHexDigit, toLower;

@safe:

package(flint.expression) size_t utf16Length(scope const(char)[] text, size_t stopAfter = size_t.max) pure nothrow @nogc
{
    size_t index, length;
    while (index < text.length && length <= stopAfter)
        length += decodeUtf8(text, index) > 0xFFFF ? 2 : 1;
    return length;
}

package(flint.expression.spel.standard) struct LiteralParser
{
    string text;
    size_t position;

    char peek() const pure nothrow @nogc
    {
        return position < text.length ? text[position] : '\0';
    }

    void skipWhitespace() pure nothrow @nogc
    {
        while (peek == ' ' || peek == '\t' || peek == '\r' || peek == '\n')
            ++position;
    }

    SpelParseException errorAt(size_t start, SpelMessage code, string detail = null)
    {
        return new SpelParseException(text, cast(int) utf16Length(text[0 .. start]), code, detail);
    }

    Any readLiteral()
    {
        const sign = peek;
        if (sign == '+' || sign == '-')
        {
            ++position;
            skipWhitespace();
        }
        if (isDigit(peek))
            return readNumber(sign == '-');
        if (peek == '.' && position + 1 < text.length && isDigit(text[position + 1]))
            throw errorAt(position, SpelMessage.MISSING_LEADING_ZERO_FOR_NUMBER);
        if (sign == '+' || sign == '-')
            throw errorAt(position, SpelMessage.OOD);
        if (peek == '\'' || peek == '"')
            return Any.of(readQuoted());
        return readIdentifier();
    }

    Any readIdentifier()
    {
        const start = position;
        char[5] name;
        while (isAlpha(peek) || isDigit(peek) || peek == '_' || peek == '$')
        {
            if (position - start == name.length)
                throw errorAt(start, SpelMessage.OOD);
            name[position - start] = toLower(peek);
            ++position;
        }
        switch (name[0 .. position - start])
        {
        case "true":
            return Any.of(true);
        case "false":
            return Any.of(false);
        case "null":
            return Any.init;
        default:
            throw errorAt(start, SpelMessage.OOD);
        }
    }

    string readQuoted()
    {
        const start = position;
        const quote = text[position++];
        size_t escapes;
        while (position < text.length)
        {
            if (text[position++] != quote)
                continue;
            if (peek == quote)
            {
                ++escapes;
                ++position;
                continue;
            }
            const quotedText = text[start + 1 .. position - 1];
            if (escapes == 0)
                return quotedText;
            return unescape(quotedText, quote, escapes);
        }
        throw errorAt(start, quote == '"' ? SpelMessage.NON_TERMINATING_DOUBLE_QUOTED_STRING
                : SpelMessage.NON_TERMINATING_QUOTED_STRING);
    }

    Any readNumber(bool negative)
    {
        const start = position;
        if (peek == '0' && position + 1 < text.length && toLower(text[position + 1]) == 'x')
            return readHex(negative);
        scanDigits();
        const fractional = scanFraction();
        const exponent = scanExponent();
        const suffix = toLower(peek);
        const digits = text[start .. position];
        if (fractional && suffix == 'l' && !exponent)
            throw errorAt(start, SpelMessage.REAL_CANNOT_BE_LONG);
        const isFloat = suffix == 'f';
        const hasRealSuffix = isFloat || suffix == 'd';
        if (hasRealSuffix)
            ++position;
        if (fractional || exponent || hasRealSuffix)
            return readReal(digits, start, negative, isFloat);
        return readInteger(digits, start, negative, suffix == 'l');
    }

    Any readInteger(string digits, size_t start, bool negative, bool isLong)
    {
        if (isLong)
            ++position;
        const parsed = tryParseLong(digits);
        if (!parsed.ok || (!isLong && parsed.value > int.max))
            throw errorAt(start, isLong ? SpelMessage.NOT_A_LONG : SpelMessage.NOT_AN_INTEGER, digits);
        return integerValue(parsed.value, negative, isLong);
    }

    void scanDigits() pure nothrow @nogc
    {
        while (isDigit(peek))
            ++position;
    }

    bool scanFraction() pure nothrow @nogc
    {
        if (peek != '.' || position + 1 == text.length || !isDigit(text[position + 1]))
            return false;
        ++position;
        scanDigits();
        return true;
    }

    bool scanExponent() pure nothrow @nogc
    {
        if (toLower(peek) != 'e')
            return false;
        ++position;
        if (peek == '+' || peek == '-')
            ++position;
        scanDigits();
        return true;
    }

    Any readHex(bool negative)
    {
        const start = position;
        position += 2;
        const digitsStart = position;
        while (isHexDigit(peek))
            ++position;
        const digits = text[digitsStart .. position];
        const isLong = toLower(peek) == 'l';
        if (isLong)
            ++position;
        const parsed = parseHex(digits, isLong ? long.max : int.max);
        if (!parsed.ok)
            throw errorAt(start, isLong ? SpelMessage.NOT_A_LONG : SpelMessage.NOT_AN_INTEGER, digits);
        return integerValue(parsed.value, negative, isLong);
    }

    Any readReal(string digits, size_t start, bool negative, bool isFloat)
    {
        if (isFloat)
        {
            const parsed = tryParseFloat(digits);
            if (parsed.ok)
                return Any.of(negative ? -parsed.value : parsed.value);
        }
        else
        {
            const parsed = tryParseDouble(digits);
            if (parsed.ok)
                return Any.of(negative ? -parsed.value : parsed.value);
        }
        throw errorAt(start, SpelMessage.NOT_A_REAL, text[start .. position]);
    }
}

private char[] unescape(string quotedText, char quote, size_t escapes) pure nothrow
{
    auto decoded = new char[quotedText.length - escapes];
    for (size_t i, j; i < quotedText.length; ++i)
    {
        const c = quotedText[i];
        decoded[j++] = c;
        if (c == quote)
            ++i;
    }
    return decoded;
}

private ParsedLong parseHex(scope const(char)[] digits, long limit) pure nothrow @nogc
{
    if (digits.length == 0)
        return ParsedLong.init;
    long value;
    foreach (const c; digits)
    {
        const digit = isDigit(c) ? c - '0' : toLower(c) - 'a' + 10;
        if (value > (limit - digit) / 16)
            return ParsedLong.init;
        value = value * 16 + digit;
    }
    return ParsedLong(true, value);
}

private Any integerValue(long magnitude, bool negative, bool isLong) pure nothrow @nogc
{
    const value = negative ? -magnitude : magnitude;
    return isLong ? Any.of(value) : Any.of(cast(int) value);
}
