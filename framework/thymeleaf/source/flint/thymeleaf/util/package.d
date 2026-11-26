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
 * lib/thymeleaf/src/main/java/org/thymeleaf/util/ObjectUtils.java
 * Modified by the Flint authors.
 */
module flint.thymeleaf.util;

public import flint.thymeleaf.util.loggingutils : LoggingUtils;

import flint.engine.aot.any : Any;
import std.typecons : Nullable;

@safe:

/// General operations on values used by Thymeleaf expressions.
final class ObjectUtils
{
    @disable this();

    /// Use the fallback only when the target represents null (R5, R23).
    static T nullSafe(T)(T target, T defaultValue) pure nothrow @nogc
    {
        alias Value = typeof(cast() target);
        static if (is(Value == Any) || is(Value == Nullable!U, U))
            return target.isNull() ? defaultValue : target;
        else static if (is(T == class) || is(T == interface))
            return target is null ? defaultValue : target;
        else
            return target;
    }
}
