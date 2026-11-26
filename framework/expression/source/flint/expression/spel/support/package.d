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
module flint.expression.spel.support;

import core.atomic : atomicLoad, atomicStore, MemoryOrder;
import flint.core.convert : TypeDescriptor;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : DescriptorTable, PropertyDescriptor;
import flint.expression : AccessException, EvaluationContext, PropertyAccessor, TypedValue;
import flint.expression.spel.context : EvaluationContextAccess, descriptorProperty, propertyTargetType;
import flint.java.lang : NullPointerException;
import flint.java.util : ArrayList, List;
import std.typecons : Rebindable;

@safe:

/// The reusable SpEL context for a root object and named variables.
class StandardEvaluationContext : EvaluationContextAccess
{
    protected override final bool isStandardContext() nothrow @nogc
    {
        return typeid(cast(Object) this) is typeid(StandardEvaluationContext);
    }

    // Readers take a single snapshot. Published entries and root wrappers are never modified.
    private TypedValue* root;
    private Bindings* variables;
    private Rebindable!(const DescriptorTable) descriptors;
    private List!PropertyAccessor propertyAccessors;

    /// Start with a null root and no variables.
    this()
    {
    }

    /// Start with the supplied root and no variables.
    this(Any rootObject)
    {
        if (!rootObject.isNull())
            root = new TypedValue(rootObject);
    }

    /// Change the default root for subsequent evaluations.
    void setRootObject(Any rootObject)
    {
        publishRoot(rootObject, null);
    }

    /// Change the root and its declared type, without inferring the type from the value.
    void setRootObject(Any rootObject, TypeDescriptor typeDescriptor)
    {
        publishRoot(rootObject, typeDescriptor);
    }

    private void publishRoot(Any value, TypeDescriptor type)
    {
        auto next = value.isNull() && type is null ? null : new TypedValue(value, type);
        atomicStore!(MemoryOrder.rel)(root, next);
    }

    override TypedValue getRootObject()
    {
        return readRootObject();
    }

    /// Supply the frozen AOT property descriptors during context setup, before publishing this context.
    final void setDescriptorTable(const DescriptorTable table) nothrow @nogc
    {
        descriptors = table;
    }

    protected override final const(DescriptorTable) descriptorTable() const nothrow @nogc
    {
        return descriptors.get();
    }

    /// The live list of property accessors, with the built-in AOT reader by default.
    override List!PropertyAccessor getPropertyAccessors()
    {
        if (auto current = configuredPropertyAccessors())
            return current;
        synchronized (this)
        {
            if (auto current = configuredPropertyAccessors())
                return current;
            auto initial = new ArrayList!PropertyAccessor;
            initial.add(new DescriptorPropertyAccessor);
            setPropertyAccessors(initial);
            return initial;
        }
    }

    /// Replace the live list of accessors. Configure the list before sharing the context.
    void setPropertyAccessors(List!PropertyAccessor accessors)
    {
        atomicStore!(MemoryOrder.rel)(propertyAccessors, accessors);
    }

    /// Insert before the final accessor, which is normally the built-in AOT reader.
    void addPropertyAccessor(PropertyAccessor accessor)
    {
        auto accessors = getPropertyAccessors();
        accessors.add(accessors.size() - 1, accessor);
    }

    /// Remove the supplied accessor, if present.
    bool removePropertyAccessor(PropertyAccessor accessor)
    {
        return getPropertyAccessors().remove(accessor);
    }

    protected override final List!PropertyAccessor configuredPropertyAccessors() nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.acq)(propertyAccessors);
    }

    /// Store or replace a variable. A null value removes its binding.
    override void setVariable(string name, Any value)
    {
        if (name is null)
            return;
        synchronized (this)
        {
            auto entries = readBindings();
            const index = insertionIndex(entries, name);
            const present = index < entries.length && entries[index].name == name;
            const remove = value.isNull();
            if (remove && !present)
                return;
            if (remove && entries.length == 1)
            {
                atomicStore!(MemoryOrder.rel)(variables, cast(Bindings*) null);
                return;
            }

            const newLength = entries.length - (present ? 1 : 0) + (remove ? 0 : 1);
            auto next = new Binding[newLength];
            next[0 .. index] = entries[0 .. index];
            const nextTail = index + (remove ? 0 : 1);
            const oldTail = index + (present ? 1 : 0);
            next[nextTail .. $] = entries[oldTail .. $];
            if (!remove)
                next[index] = Binding(name, value);
            atomicStore!(MemoryOrder.rel)(variables, new Bindings(next));
        }
    }

    override Any lookupVariable(string name)
    {
        if (name is null)
            throw new NullPointerException("Variable name must not be null");
        return readVariable(name);
    }

    protected override final TypedValue readRootObject() nothrow @nogc
    {
        auto snapshot = atomicLoad!(MemoryOrder.acq)(root);
        return snapshot is null ? TypedValue.NULL : *snapshot;
    }

    protected override final Any readVariable(string name) nothrow @nogc
    {
        auto entries = readBindings();
        const index = insertionIndex(entries, name);
        return index < entries.length && entries[index].name == name ? entries[index].value : Any.init;
    }

    private Binding[] readBindings() nothrow @nogc
    {
        if (auto snapshot = atomicLoad!(MemoryOrder.acq)(variables))
            return snapshot.entries;
        return null;
    }
}

private final class DescriptorPropertyAccessor : PropertyAccessor
{
    override string[] getSpecificTargetClasses()
    {
        return null;
    }

    override bool canRead(EvaluationContext context, Any target, string name)
    {
        auto member = property(context, target, name);
        return member !is null && member.get !is null;
    }

    override TypedValue read(EvaluationContext context, Any target, string name)
    {
        auto member = property(context, target, name);
        if (member is null || member.get is null)
            throw new AccessException("Cannot read property " ~ name);
        return TypedValue(member.get(target));
    }

    override bool canWrite(EvaluationContext, Any, string)
    {
        return false;
    }

    override void write(EvaluationContext, Any, string name, Any)
    {
        throw new AccessException("Cannot write property " ~ name);
    }

    private static const(PropertyDescriptor)* property(EvaluationContext context, const ref Any target, string name)
    {
        auto standard = cast(StandardEvaluationContext) context;
        if (standard is null || target.isNull())
            return null;
        return descriptorProperty(standard.descriptorTable(), target, propertyTargetType(target), name);
    }
}

private struct Binding
{
    string name;
    Any value;
}

private struct Bindings
{
    Binding[] entries;
}

private size_t insertionIndex(scope const(Binding)[] entries, string name) pure nothrow @nogc
{
    size_t lower, upper = entries.length;
    while (lower < upper)
    {
        const middle = lower + (upper - lower) / 2;
        if (entries[middle].name < name)
            lower = middle + 1;
        else
            upper = middle;
    }
    return lower;
}
