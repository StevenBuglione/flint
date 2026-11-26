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
 * lib/thymeleaf/src/main/java/org/thymeleaf/expression/IExpressionObjects.java
 * Modified by the Flint authors.
 */
module flint.thymeleaf.expression;

import flint.engine.aot.any : Any;
import flint.java.util : Set;

@safe:

/// The named utility objects available to template expressions.
interface IExpressionObjects
{
    /// Suffix for the registered variant of an object used in restricted mode.
    static immutable string RESTRICTED_NAME_MODIFIER = "[restricted]";

    /// The number of registered names.
    int size();

    /// Whether the object name is registered.
    bool containsObject(string name);

    /// All registered names (R10).
    Set!string getObjectNames();

    /// The object registered with this name, or Any.init when absent (R23).
    Any getObject(string name);
}
