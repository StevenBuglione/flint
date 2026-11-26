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
 * Modified by the Flint authors.
 */
module flint.thymeleaf.context;

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
