/*
 * Copyright (c) 2011-2026 Thymeleaf (http://www.thymeleaf.org)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Ported from thymeleaf 3.1.7.RELEASE:
 * lib/thymeleaf/src/main/java/org/thymeleaf/context/IContext.java
 * lib/thymeleaf/src/main/java/org/thymeleaf/context/IdentifierSequences.java
 * lib/thymeleaf/src/main/java/org/thymeleaf/context/ILazyContextVariable.java
 * lib/thymeleaf/src/main/java/org/thymeleaf/context/LazyContextVariable.java
 * Modified by the Flint authors.
 */
module flint.thymeleaf.context;

import core.atomic : MemoryOrder, atomicLoad, atomicStore;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : Locale, Set;
import flint.thymeleaf.exceptions : TemplateProcessingException;
import std.typecons : Nullable;

@safe:

/// Locale and variables used to process a template.
interface IContext
{
    /// The locale used during template processing.
    Locale getLocale();

    /// Whether the context contains the named variable.
    bool containsVariable(string name);

    /// The names of the variables contained in this context (R10).
    Set!string getVariableNames();

    /// The named value, or Any.init for null or a missing variable (R23).
    Any getVariable(string name);
}

/// Per-context counts used to generate distinct template identifiers.
final class IdentifierSequences
{
    private alias Identifier = Nullable!string;

    // Reuse the string-to-ulong table already instantiated by Java collections. Each count is a 32-bit value.
    private ulong[string] nextCounts;

    /// Starts the next count at one for each identifier, with storage allocated on first use.
    this() pure nothrow @nogc
    {
    }

    /// Return and advance this identifier's counter.
    int getAndIncrementIDSeq(Identifier id)
    {
        auto key = requireId(id);
        if (auto next = lookup(key))
        {
            const current = cast(int)*next;
            *next = cast(uint) current + 1;
            return current;
        }
        nextCounts[key] = 2;
        return 1;
    }

    /// Look up this identifier's next count without advancing it.
    int getNextIDSeq(Identifier id) const
    {
        const key = requireId(id);
        const next = lookup(key);
        return next is null ? 1 : cast(int)*next;
    }

    /// Look up the last returned count, or reject an identifier that has yet to advance.
    int getPreviousIDSeq(Identifier id) const
    {
        const key = requireId(id);
        const next = lookup(key);
        if (next is null)
            throw new TemplateProcessingException("Cannot obtain previous ID count for ID \"" ~ key ~ "\"");
        return cast(int)(cast(uint)*next - 1);
    }

    private inout(ulong)* lookup(string key) inout pure nothrow @nogc
    {
        return key in nextCounts;
    }

    private static string requireId(Identifier id)
    {
        if (id.isNull)
            throw new IllegalArgumentException("ID cannot be null");
        return id.get;
    }
}

/// A context variable whose value is resolved only when requested (R23).
interface ILazyContextVariable
{
    /// Resolve and return the variable's value.
    Any getValue();
}

/// Resolves a typed value lazily and publishes its erased value once (R23).
abstract class LazyContextVariable(T) : ILazyContextVariable
{
    private LazyValue cached;

    protected this()
    {
    }

    /// Return the cached value. If loading fails, the next read can retry.
    final override Any getValue()
    {
        return cached.get(this, () => Any.of(loadValue()));
    }

    /// Compute the value on the first successful load.
    protected abstract T loadValue();
}

private struct LazyValue
{
    private shared bool published;
    private bool loading; // Protected by the instance monitor.
    private bool resolved; // Protected by the instance monitor.
    private Any value;

    Any get(Object monitor, scope Any delegate() @safe load)
    {
        if (atomicLoad!(MemoryOrder.acq)(published))
            return value;

        synchronized (monitor)
        {
            if (!resolved)
            {
                const outermost = !loading;
                loading = true;
                scope (exit)
                {
                    if (outermost)
                    {
                        loading = false;
                        // A recursive load can resolve under the lock. Publish only once
                        // no outer loader can still replace the multiword Any.
                        if (resolved)
                            atomicStore!(MemoryOrder.rel)(published, true);
                    }
                }
                auto loaded = load();
                value = loaded.isNull() ? Any.init : loaded;
                resolved = true;
            }
            return value;
        }
    }
}
