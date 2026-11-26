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
 * Modified by the Flint authors.
 */
module flint.expression.spel.standard.property;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : DescriptorTable;
import flint.expression.spel : SpelEvaluationException, SpelMessage;
import flint.expression.spel.standard.literal : LiteralParser, utf16Length;
import std.ascii : toLower;

@safe:
package(flint.expression.spel.standard):

struct PropertyStep
{
    string name;
    size_t position;
    bool nullSafe;
}

/// Recognize a complete root-relative property path. The scalar parser handles other expressions.
immutable(PropertyStep)[] parsePropertyPath(string source)
{
    auto reader = LiteralParser(source);
    reader.skipWhitespace();

    bool nullSafe;
    const explicitRoot = reader.peek == '#';
    if (explicitRoot)
    {
        ++reader.position;
        reader.skipWhitespace();
        const root = reader.readIdentifierName();
        if ((root != "root" && root != "this") || !readSeparator(reader, nullSafe))
            return null;
    }

    PropertyStep[] steps;
    while (true)
    {
        reader.skipWhitespace();
        const position = reader.position;
        const name = reader.readIdentifierName();
        if (name is null || (!explicitRoot && steps.length == 0 && isLiteralName(name)))
            return null;
        steps ~= PropertyStep(name, position, nullSafe);
        if (!readSeparator(reader, nullSafe))
            return reader.position == source.length ? steps.idup : null;
    }
}

private bool readSeparator(ref LiteralParser reader, out bool nullSafe) pure nothrow @nogc
{
    reader.skipWhitespace();
    if (reader.peek == '.')
    {
        ++reader.position;
        return true;
    }
    if (reader.peek == '?' && reader.position + 1 < reader.text.length && reader.text[reader.position + 1] == '.')
    {
        reader.position += 2;
        nullSafe = true;
        return true;
    }
    return false;
}

private bool isLiteralName(scope const(char)[] name) pure nothrow @nogc
{
    char[5] lower;
    if (name.length > lower.length)
        return false;
    foreach (i, c; name)
        lower[i] = toLower(c);
    const word = lower[0 .. name.length];
    return word == "null" || word == "true" || word == "false";
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
            throw propertyError(source, step, SpelMessage.PROPERTY_OR_FIELD_NOT_READABLE_ON_NULL);
        }
        const type = root.typeName();
        const descriptor = table is null ? null : table.find(type);
        const member = descriptor is null ? null : descriptor.property(step.name);
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

private SpelEvaluationException propertyError(string source, const ref PropertyStep step,
        SpelMessage code, string detail = null, Throwable cause = null)
{
    return new SpelEvaluationException(cast(int) utf16Length(source[0 .. step.position]), code,
            step.name, detail, cause);
}
