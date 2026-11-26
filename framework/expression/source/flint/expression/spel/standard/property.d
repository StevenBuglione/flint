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
 * spring-expression/src/main/java/org/springframework/expression/spel/ast/PropertyOrFieldReference.java
 * Also from ast/Indexer.java.
 * Modified by the Flint authors.
 */
module flint.expression.spel.standard.property;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, DescriptorTable, TypeKind;
import flint.engine.aot.text : ParsedLong, decimal, decodeUtf8;
import flint.expression : EvaluationContext, PropertyAccessor;
import flint.expression.spel : SpelEvaluationException, SpelMessage;
import flint.expression.spel.standard.literal : LiteralParser, utf16Length;
import flint.expression.spel.context : EvaluationContextAccess, descriptorProperty, propertyTargetType;
import flint.java.lang : IllegalStateException, IndexOutOfBoundsException;
import flint.java.util : List;

@safe:
package(flint.expression.spel.standard):

struct PropertyStep
{
    // A null name denotes a read of an index plan in the enclosing expression.
    string name;
    size_t position;
    bool nullSafe;
    uint index;
}

enum PropertySeparator : ubyte
{
    absent,
    dot,
    safeDot,
    bracket,
}

PropertySeparator readSeparator(ref LiteralParser reader) pure nothrow @nogc
{
    reader.skipWhitespace();
    if (reader.peek == '.')
    {
        ++reader.position;
        return PropertySeparator.dot;
    }
    if (reader.peek == '?' && reader.position + 1 < reader.text.length && reader.text[reader.position + 1] == '.')
    {
        reader.position += 2;
        return PropertySeparator.safeDot;
    }
    if (reader.peek == '[')
        return PropertySeparator.bracket;
    return PropertySeparator.absent;
}

/// Apply one descriptor-backed path step at the Spring API boundary.
void readPathStep(string source, const ref PropertyStep step, ref Any root, EvaluationContext context,
        EvaluationContextAccess standard, const DescriptorTable table, const ref Any index)
{
    if (step.nullSafe && root.isNull())
        return;
    if (step.name is null)
    {
        root = readIndex(source, step, root, table, index);
        return;
    }
    const type = propertyTargetType(root);
    try
    {
        auto accessors = configuredAccessors(context, standard);
        if (readProperty(context, accessors, table, root, type, step.name))
            return;
    }
    catch (SpelEvaluationException error)
        throw error;
    catch (Exception error)
        throw evaluationErrorAt(source, step.position, SpelMessage.EXCEPTION_DURING_PROPERTY_READ,
                step.name, error.msg, error);
    if (root.isNull())
        throw evaluationErrorAt(source, step.position, SpelMessage.PROPERTY_OR_FIELD_NOT_READABLE_ON_NULL, step.name);
    throw evaluationErrorAt(source, step.position, SpelMessage.PROPERTY_OR_FIELD_NOT_READABLE, step.name, type);
}

private Any readIndex(string source, const ref PropertyStep step, ref Any target,
        const DescriptorTable table, const ref Any value)
{
    if (target.isNull())
        throw evaluationErrorAt(source, step.position, SpelMessage.CANNOT_INDEX_INTO_NULL_VALUE);
    if (value.isNull())
        throw new IllegalStateException("No index");
    const type = target.typeName();
    const isString = type == "string";
    const descriptor = isString ? null : arrayIndexDescriptor(source, step.position, type, table);

    const index = convertIndexToInt(source, step.position, value);
    const length = isString ? 0 : descriptor.length(target);
    if (index < 0) // Reuse the formatter for the bounds diagnostics until the Java exception leaves share it.
        throw new IndexOutOfBoundsException("Index out of range: " ~ decimal(index));
    if (isString)
        return Any.of(readStringIndex(source, step.position, target.get!string, index));
    if (cast(size_t) index >= length)
        throw evaluationErrorAt(source, step.position, SpelMessage.ARRAY_INDEX_OUT_OF_BOUNDS,
                decimal(length), decimal(index));
    return descriptor.element(target, index);
}

private int convertIndexToInt(string source, size_t position, const ref Any value)
{
    // Any reads an integral value as int only when it fits.
    if (value.holds!int)
        return value.get!int;

    const type = value.typeName();
    if (type == "double" || type == "float")
    {
        const number = value.get!double;
        // Spring checks the range after truncation. Ordered comparisons also reject NaN.
        if (number > cast(double) int.min - 1 && number < cast(double) int.max + 1)
            return cast(int) number;
    }
    // Spring's CharacterToNumberFactory widens the UTF-16 value through a signed short.
    if (type == "wchar" || type == "char")
        return cast(short) value.get!wchar;
    if (type == "string")
    {
        const text = value.get!string;
        if (text.length == 0)
            throw new IllegalStateException("Null conversion result for value []");
        const parsed = parseIndexInteger(text);
        if (parsed.ok)
            return cast(int) parsed.value;
    }

    throw evaluationErrorAt(source, position, SpelMessage.TYPE_CONVERSION_ERROR, type, "int");
}

// NumberUtils strips Java whitespace throughout the string. Only # and 0x/0X select hexadecimal.
private ParsedLong parseIndexInteger(scope const(char)[] text) pure nothrow @nogc
{
    size_t offset;
    auto unit = nextIndexCharacter(text, offset);
    const negative = unit == '-';
    if (negative || unit == '+')
        unit = nextIndexCharacter(text, offset);

    uint radix = 10;
    if (unit == '0')
    {
        auto afterZero = offset;
        const prefix = nextIndexCharacter(text, afterZero);
        if ((prefix | 0x20) == 'x')
        {
            unit = '#';
            offset = afterZero;
        }
    }
    if (unit == '#')
    {
        radix = 16;
        unit = nextIndexCharacter(text, offset);
    }
    if (unit == endOfIndexText)
        return ParsedLong.init;

    long magnitude;
    const limit = cast(long) int.max + negative;
    do
    {
        const digit = indexDigit(unit);
        if (digit >= radix)
            return ParsedLong.init;
        magnitude = magnitude * radix + digit;
        if (magnitude > limit)
            return ParsedLong.init;
        unit = nextIndexCharacter(text, offset);
    }
    while (unit != endOfIndexText);
    return ParsedLong(true, negative ? -magnitude : magnitude);
}

private enum endOfIndexText = uint.max;

// Equivalent to Java Character.isWhitespace for the code points of a UTF-8 string.
private uint nextIndexCharacter(scope const(char)[] text, ref size_t offset) pure nothrow @nogc
{
    while (offset < text.length)
    {
        const uint unit = decodeUtf8(text, offset);
        if (unit - 9 <= 4 || unit - 0x1C <= 4 || unit == 0x1680 || (unit - 0x2000 <= 10 && unit != 0x2007)
                || unit - 0x2028 <= 1 || unit == 0x205F || unit == 0x3000)
            continue;
        return unit;
    }
    return endOfIndexText;
}

// Integer.parseInt calls Character.digit on UTF-16 code units. The BMP decimal zeroes match JDK 21.0.13.1.
private uint indexDigit(uint unit) pure nothrow @nogc
{
    static immutable ushort[] decimalZeros = [
        0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6, 0x0C66, 0x0CE6,
        0x0D66, 0x0DE6, 0x0E50, 0x0ED0, 0x0F20, 0x1040, 0x1090, 0x17E0, 0x1810, 0x1946, 0x19D0,
        0x1A80, 0x1A90, 0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620, 0xA8D0, 0xA900, 0xA9D0, 0xA9F0,
        0xAA50, 0xABF0, 0xFF10
    ];
    if (unit - '0' <= 9)
        return unit - '0';
    const letter = (unit | 0x20) - 'a';
    if (letter <= 5)
        return 10 + letter;
    if (unit - 0xFF21 <= 5)
        return 10 + unit - 0xFF21;
    if (unit - 0xFF41 <= 5)
        return 10 + unit - 0xFF41;
    if (unit >= 0x80 && unit <= 0xFFFF)
        foreach (zero; decimalZeros)
            if (unit - zero <= 9)
                return unit - zero;
    return uint.max;
}

private const(Descriptor) arrayIndexDescriptor(string source, size_t position, string type, const DescriptorTable table)
{
    const descriptor = table is null ? null : table.find(type);
    if (descriptor is null || descriptor.kind != TypeKind.array || descriptor.length is null || descriptor
            .element is null)
        throw evaluationErrorAt(source, position, SpelMessage.INDEXING_NOT_SUPPORTED_FOR_TYPE, type);
    return descriptor;
}

private string readStringIndex(string source, size_t position, string text, int index)
{
    size_t units;
    const unit = stringUnitAt(text, index, units);
    if (unit is null)
        throw evaluationErrorAt(source, position, SpelMessage.STRING_INDEX_OUT_OF_BOUNDS,
                decimal(units), decimal(index));
    return unit;
}

// R14 keeps Java's UTF-16 offsets. D-SPEL-4 maps each lone surrogate to U+FFFD.
private string stringUnitAt(string text, size_t index, out size_t units) pure nothrow @nogc
{
    for (size_t offset; offset < text.length;)
    {
        const start = offset;
        const point = decodeUtf8(text, offset);
        units += point > 0xFFFF ? 2 : 1;
        if (index < units)
            return point > 0xFFFF || point == 0xFFFD ? "\uFFFD" : text[start .. offset];
    }
    return null;
}

private List!PropertyAccessor configuredAccessors(EvaluationContext context, EvaluationContextAccess standard)
{
    if (standard !is null && standard.isStandardContext())
        return standard.configuredPropertyAccessors();
    return context is null ? null : context.getPropertyAccessors();
}

private bool readProperty(EvaluationContext context, List!PropertyAccessor accessors,
        const DescriptorTable table, ref Any target, string type, string name)
{
    if (accessors !is null)
    {
        const descriptor = table is null ? null : table.find(type);
        return readWithAccessors(context, accessors, descriptor, target, type, name);
    }
    if (target.isNull())
        return false;
    auto member = descriptorProperty(table, target, type, name);
    if (member is null || member.get is null)
        return false;
    target = member.get(target);
    return true;
}

private enum Match : ubyte
{
    exact,
    inherited,
    generic,
    none,
}

private struct AccessorCandidate
{
    PropertyAccessor accessor;
    Match match;
}

private bool readWithAccessors(EvaluationContext context, List!PropertyAccessor accessors,
        const Descriptor descriptor, ref Any target, string type, string name)
{
    const count = accessors.size();
    AccessorCandidate[8] local;
    auto candidates = count <= cast(int) local.length ? local[0 .. count] : new AccessorCandidate[count];
    foreach (index; 0 .. count)
    {
        auto accessor = accessors.get(index);
        const match = matchTarget(accessor.getSpecificTargetClasses(), target, type, descriptor);
        candidates[index] = AccessorCandidate(accessor, match);
    }
    static immutable ranks = [Match.exact, Match.inherited, Match.generic];
    foreach (rank; ranks)
        foreach (candidate; candidates)
            if (candidate.match == rank && candidate.accessor.canRead(context, target, name))
            {
                target = candidate.accessor.read(context, target, name).getValue();
                return true;
            }
    return false;
}

private Match matchTarget(scope string[] names, const ref Any target, string type, const Descriptor desc) nothrow @nogc
{
    if (names.length == 0)
        return Match.generic;
    if (target.isNull())
        return Match.none;
    Match best = Match.none;
    foreach (candidate; names)
    {
        if (candidate == type)
            return Match.exact;
        if (candidate == target.typeName() || (desc !is null && desc.isAssignableTo(candidate)))
            best = Match.inherited;
    }
    return best;
}

pragma(inline, false) SpelEvaluationException evaluationErrorAt(string source, size_t offset,
        SpelMessage code, string detail = null, string context = null, Throwable cause = null)
{
    return new SpelEvaluationException(cast(int) utf16Length(source[0 .. offset]), code, detail, context, cause);
}
