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
 * lib/thymeleaf/src/main/java/org/thymeleaf/dialect/IDialect.java
 * lib/thymeleaf/src/main/java/org/thymeleaf/dialect/AbstractDialect.java
 * Modified by the Flint authors.
 */
module flint.thymeleaf.dialect;

@safe:

/// Base interface for extensions to Thymeleaf template processing.
interface IDialect
{
    /// The dialect's name.
    string getName();
}

/// Base implementation that retains the name supplied at construction.
class AbstractDialect : IDialect
{
    private immutable string name;

    /// Retains the name. A default-initialized D string means an empty name (R5).
    protected this(string name) nothrow @nogc
    {
        this.name = name;
    }

    /// The name supplied at construction.
    final override string getName() nothrow @nogc
    {
        return name;
    }
}
