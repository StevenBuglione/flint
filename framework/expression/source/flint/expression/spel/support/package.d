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
import flint.engine.aot.any : Any;
import flint.expression : EvaluationContext, TypedValue;
import flint.java.lang : NullPointerException;

@safe:

/// The reusable SpEL context for a root object and named variables.
class StandardEvaluationContext : EvaluationContext
{
    // Readers take a single snapshot. Published entries and root wrappers are never modified.
    private TypedValue* root;
    private Bindings* variables;

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
        auto next = rootObject.isNull() ? null : new TypedValue(rootObject);
        atomicStore!(MemoryOrder.rel)(root, next);
    }

    override TypedValue getRootObject()
    {
        return readRootObject();
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

    package(flint.expression) final TypedValue readRootObject() nothrow @nogc
    {
        auto snapshot = atomicLoad!(MemoryOrder.acq)(root);
        return snapshot is null ? TypedValue.NULL : *snapshot;
    }

    package(flint.expression) final Any readVariable(string name) nothrow @nogc
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
