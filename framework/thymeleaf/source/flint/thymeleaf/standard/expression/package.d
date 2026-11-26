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
 * lib/thymeleaf/src/main/java/org/thymeleaf/standard/expression/StandardExpressionExecutionContext.java
 * Modified by the Flint authors.
 */
module flint.thymeleaf.standard.expression;

@safe:

/// Restrictions and conversion settings for one standard expression evaluation (R15).
struct StandardExpressionExecutionContext
{
    private enum ubyte restrictVariables = 1 << 0;
    private enum ubyte restrictExternal = 1 << 1;
    private enum ubyte forbidUnsafeResults = 1 << 2;
    private enum ubyte convertTypes = 1 << 3;
    private enum ubyte normalLinkParameters = 1 << 4;
    private enum ubyte restrictedAccess = restrictVariables | restrictExternal;

    private ubyte flags;

    private this(ubyte flags) pure nothrow @nogc
    {
        this.flags = flags;
    }

    /// Restricts access to variables and external types.
    static immutable RESTRICTED = StandardExpressionExecutionContext(restrictedAccess);

    /// Restricts access and forbids unsafe expression results.
    static immutable RESTRICTED_FORBID_UNSAFE_EXP_RESULTS = StandardExpressionExecutionContext(
            restrictedAccess | forbidUnsafeResults);

    /// Restricts the link base and evaluates its parameters in normal mode.
    static immutable RESTRICTED_WITH_NORMAL_LINK_PARAMETERS = StandardExpressionExecutionContext(
            restrictedAccess | normalLinkParameters);

    /// Normal evaluation with type conversion off.
    static immutable NORMAL = StandardExpressionExecutionContext(0);

    /// Whether variable access is restricted.
    bool getRestrictVariableAccess() const pure nothrow @nogc
    {
        return (flags & restrictVariables) != 0;
    }

    /// Whether object construction and static type access are restricted.
    bool getRestrictExternalAccess() const pure nothrow @nogc
    {
        return (flags & restrictExternal) != 0;
    }

    /// Whether unsafe expression results are forbidden.
    bool getForbidUnsafeExpressionResults() const pure nothrow @nogc
    {
        return (flags & forbidUnsafeResults) != 0;
    }

    /// Whether to perform type conversion.
    bool getPerformTypeConversion() const pure nothrow @nogc
    {
        return (flags & convertTypes) != 0;
    }

    /// Use the upstream evaluation mode for link parameters.
    package StandardExpressionExecutionContext forLinkParameters() const pure nothrow @nogc
    {
        return (flags & normalLinkParameters) != 0 || (flags & restrictedAccess) == 0 ? NORMAL : RESTRICTED;
    }

    /// Preserve the restrictions and turn type conversion off.
    StandardExpressionExecutionContext withoutTypeConversion() const pure nothrow @nogc
    {
        return StandardExpressionExecutionContext(cast(ubyte)(flags & ~convertTypes));
    }

    /// Preserve the restrictions and turn type conversion on.
    StandardExpressionExecutionContext withTypeConversion() const pure nothrow @nogc
    {
        return StandardExpressionExecutionContext(cast(ubyte)(flags | convertTypes));
    }
}
