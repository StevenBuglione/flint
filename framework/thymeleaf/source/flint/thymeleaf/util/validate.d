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
 * lib/thymeleaf/src/main/java/org/thymeleaf/util/Validate.java
 * Modified by the Flint authors.
 */
module flint.thymeleaf.util.validate;

import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : Collection;

@safe:

/// Argument validation for Thymeleaf configuration and processing.
final class Validate
{
    @disable this();

    /// Require an object value (R23).
    static void notNull(const Any value, string message)
    {
        if (value.isNull())
            throw new IllegalArgumentException(message);
    }

    /// Require a nonempty collection (R10).
    static void notEmpty(T)(Collection!T values, string message)
    {
        if (values is null || values.size() == 0)
            throw new IllegalArgumentException(message);
    }

    /// Require a nonempty array of object values (R23).
    static void notEmpty(scope const(Any)[] values, string message)
    {
        if (values.length == 0)
            throw new IllegalArgumentException(message);
    }

    /// Require a true condition.
    static void isTrue(bool condition, string message)
    {
        if (!condition)
            throw new IllegalArgumentException(message);
    }
}
