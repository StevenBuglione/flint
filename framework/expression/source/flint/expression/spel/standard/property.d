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
import flint.engine.aot.text : decimal;
import flint.expression : EvaluationContext, PropertyAccessor;
import flint.expression.spel : SpelEvaluationException, SpelMessage;
import flint.expression.spel.standard.literal : LiteralParser, utf16Length;
import flint.expression.spel.context : EvaluationContextAccess, descriptorProperty, propertyTargetType;
import flint.java.lang : IndexOutOfBoundsException;
import flint.java.util : List;

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
Any readPropertyPath(string source, scope const(PropertyStep)[] steps, Any root, EvaluationContext context)
{
    auto standard = cast(EvaluationContextAccess) context;
    const table = standard is null ? null : standard.descriptorTable();
    foreach (ref step; steps)
    {
        if (step.nullSafe && root.isNull())
            continue;
        if (step.name is null)
        {
            if (root.isNull())
                throw propertyError(source, step, SpelMessage.CANNOT_INDEX_INTO_NULL_VALUE);
            root = readArrayIndex(source, step, root, table);
            continue;
        }
        const type = propertyTargetType(root);
        try
        {
            auto accessors = configuredAccessors(context, standard);
            if (readProperty(context, accessors, table, root, type, step.name))
                continue;
        }
        catch (SpelEvaluationException error)
            throw error;
        catch (Exception error)
            throw propertyError(source, step, SpelMessage.EXCEPTION_DURING_PROPERTY_READ, error.msg, error);
        if (root.isNull())
            throw propertyError(source, step, SpelMessage.PROPERTY_OR_FIELD_NOT_READABLE_ON_NULL);
        throw propertyError(source, step, SpelMessage.PROPERTY_OR_FIELD_NOT_READABLE, type);
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

private SpelEvaluationException propertyError(string source, const ref PropertyStep step,
        SpelMessage code, string detail = null, Throwable cause = null)
{
    return new SpelEvaluationException(cast(int) utf16Length(source[0 .. step.position]), code,
            step.name, detail, cause);
}
