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
 * lib/thymeleaf/src/main/java/org/thymeleaf/context/ILazyContextVariable.java
 * lib/thymeleaf/src/main/java/org/thymeleaf/context/LazyContextVariable.java
 * Modified by the Flint authors.
 */
module flint.thymeleaf.context;

import core.atomic : MemoryOrder, atomicLoad, atomicStore;
import flint.engine.aot.any : Any;
import flint.java.util : Locale, Set;

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
