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
import flint.engine.aot.descriptor : DescriptorTable, PropertyDescriptor, TypeKind;
import flint.engine.aot.name : canonicalTypeName;
import flint.engine.aot.text : decimal;
import flint.expression.spel : SpelEvaluationException, SpelMessage;
import flint.expression.spel.standard.literal : LiteralParser, utf16Length;
import flint.java.lang : IndexOutOfBoundsException;
import std.ascii : isAlphaNum;

@safe:
package(flint.expression.spel.standard):

struct PropertyStep
{
    // A null name denotes an array index.
    string name;
    size_t position;
    bool nullSafe;
    int index;
}

enum PropertySeparator : ubyte
{
    absent,
    dot,
    safeDot,
    bracket,
}

PropertyStep readPropertyStep(ref LiteralParser reader, bool nullSafe)
{
    reader.skipWhitespace();
    const position = reader.position;
    if (reader.peek == '[')
    {
        ++reader.position;
        reader.skipWhitespace();
        const value = reader.readLiteral();
        if (value.typeName() != "int")
            throw reader.errorAt(position, SpelMessage.OOD);
        reader.skipWhitespace();
        if (reader.peek != ']')
            throw reader.errorAt(reader.position, SpelMessage.OOD);
        ++reader.position;
        return PropertyStep(null, position, nullSafe, value.get!int);
    }
    const name = reader.readIdentifierName();
    if (name is null)
        throw reader.errorAt(position, SpelMessage.OOD);
    return PropertyStep(name, position, nullSafe);
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

/// Read through erased AOT accessors at the Spring API boundary.
Any readPropertyPath(string source, scope const(PropertyStep)[] steps, Any root, const DescriptorTable table)
{
    foreach (ref step; steps)
    {
        if (root.isNull())
        {
            if (step.nullSafe)
                continue;
            if (step.name is null)
                throw propertyError(source, step, SpelMessage.CANNOT_INDEX_INTO_NULL_VALUE);
            throw propertyError(source, step, SpelMessage.PROPERTY_OR_FIELD_NOT_READABLE_ON_NULL);
        }
        if (step.name is null)
        {
            root = readArrayIndex(source, step, root, table);
            continue;
        }
        const type = targetType(root);
        auto member = findProperty(table, type, step.name);
        if (member is null && type != root.typeName())
            member = findProperty(table, root.typeName(), step.name);
        if (member is null || member.get is null)
            throw propertyError(source, step, SpelMessage.PROPERTY_OR_FIELD_NOT_READABLE, type);
        try
            root = member.get(root);
        catch (SpelEvaluationException error)
            throw error;
        catch (Exception error)
            throw propertyError(source, step, SpelMessage.EXCEPTION_DURING_PROPERTY_READ, error.msg, error);
    }
    return root;
}

private Any readArrayIndex(string source, const ref PropertyStep step, ref Any target, const DescriptorTable table)
{
    const type = target.typeName();
    const descriptor = table is null ? null : table.find(type);
    if (descriptor is null || descriptor.kind != TypeKind.array || descriptor.length is null || descriptor
            .element is null)
        throw new SpelEvaluationException(cast(int) utf16Length(source[0 .. step.position]),
                SpelMessage.INDEXING_NOT_SUPPORTED_FOR_TYPE, type);

    const length = descriptor.length(target);
    if (step.index < 0)
        throw new IndexOutOfBoundsException(step.index);
    if (cast(size_t) step.index >= length)
        throw new SpelEvaluationException(cast(int) utf16Length(source[0 .. step.position]),
                SpelMessage.ARRAY_INDEX_OUT_OF_BOUNDS, decimal(length), decimal(step.index), null);
    return descriptor.element(target, step.index);
}

private string targetType(const ref Any target) pure nothrow
{
    const boxedType = target.typeName();
    if (auto object = target.asObject())
    {
        const runtimeType = typeid(object).name;
        if (runtimeType != boxedType)
            return canonicalTargetName(runtimeType);
    }
    return boxedType;
}

// A simple eponymous class instance is named "module.Owner!Arg.Owner" by both compilers.
// Its canonical name is a slice. Delegate more complex names to the shared canonicalizer.
private string canonicalTargetName(string name) pure nothrow
{
    size_t ownerStart;
    foreach (position, character; name)
    {
        if (character == '.')
            ownerStart = position + 1;
        if (character != '!')
            continue;

        const owner = name[ownerStart .. position];
        size_t end = position + 1;
        while (end < name.length && (isAlphaNum(name[end]) || name[end] == '_' || name[end] >= 0x80))
            ++end;
        if (end > position + 1 && end < name.length && name[end] == '.' && name[end + 1 .. $] == owner)
            return name[0 .. end];
        return canonicalTypeName(name);
    }
    return name;
}

private const(PropertyDescriptor)* findProperty(const DescriptorTable table, string type, string name) nothrow
{
    const descriptor = table is null ? null : table.find(type);
    return descriptor is null ? null : descriptor.property(name);
}

private SpelEvaluationException propertyError(string source, const ref PropertyStep step,
        SpelMessage code, string detail = null, Throwable cause = null)
{
    return new SpelEvaluationException(cast(int) utf16Length(source[0 .. step.position]), code,
            step.name, detail, cause);
}
