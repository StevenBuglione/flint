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
 * spring-expression/src/main/java/org/springframework/expression/spel/support/StandardEvaluationContext.java
 * Modified by the Flint authors.
 */
module flint.expression.spel.context;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : DescriptorTable, PropertyDescriptor;
import flint.engine.aot.name : canonicalTypeName;
import flint.expression : EvaluationContext, PropertyAccessor, TypedValue;
import flint.java.util : List;
import std.ascii : isAlphaNum;

@safe:

// Lets the parser link without the concrete context and its optional accessor collection.
package(flint.expression) interface EvaluationContextAccess : EvaluationContext
{
    bool isStandardContext() nothrow @nogc;
    TypedValue readRootObject() nothrow @nogc;
    Any readVariable(string name) nothrow @nogc;
    const(DescriptorTable) descriptorTable() const nothrow @nogc;
    List!PropertyAccessor configuredPropertyAccessors() nothrow @nogc;
}

package(flint.expression) string propertyTargetType(const ref Any target) pure nothrow
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

package(flint.expression) const(PropertyDescriptor)* descriptorProperty(const DescriptorTable table,
        const ref Any target, string type, string name) nothrow
{
    auto member = findProperty(table, type, name);
    if (member is null && type != target.typeName())
        return findProperty(table, target.typeName(), name);
    return member;
}
