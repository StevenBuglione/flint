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
 * lib/thymeleaf/src/main/java/org/thymeleaf/util/StringUtils.java
 * Modified by the Flint authors.
 */
module flint.thymeleaf.util.stringutils;

@safe:

/// String operations used by Thymeleaf (R1).
struct StringUtils
{
    @disable this();

    /// Whether the string has no characters. A null string is empty (R5).
    static bool isEmpty(scope string target) pure nothrow @nogc
    {
        return target.length == 0;
    }
}
