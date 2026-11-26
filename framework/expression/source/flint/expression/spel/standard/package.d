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
 * spring-expression/src/main/java/org/springframework/expression/spel/standard/SpelExpressionParser.java
 * Also from SpelExpression.java and InternalSpelExpressionParser.java.
 * Modified by the Flint authors.
 */
module flint.expression.spel.standard;

import flint.engine.aot.any : Any;
import flint.expression : Expression, ExpressionParser;
import flint.expression.spel : SpelEvaluationException, SpelMessage;
import flint.expression.spel.standard.literal : parseLiteral, utf16Length;

@safe:

/// A reusable parser for SpEL source.
class SpelExpressionParser : ExpressionParser
{
    override Expression parseExpression(string expressionString)
    {
        return parseRaw(expressionString);
    }

    /// Parse an expression without template delimiters.
    SpelExpression parseRaw(string expressionString)
    {
        enum maxLength = 10_000;
        if (expressionString.length > maxLength && utf16Length(expressionString, maxLength) > maxLength)
            throw new SpelEvaluationException(SpelMessage.MAX_EXPRESSION_LENGTH_EXCEEDED, "10000");
        return new SpelExpression(expressionString, parseLiteral(expressionString));
    }
}

/// The source and value of a parsed SpEL expression.
class SpelExpression : Expression
{
    private string expressionString;
    private Any value;

    package(flint.expression) this(string expressionString, Any value)
    {
        this.expressionString = expressionString;
        this.value = value;
    }

    override string getExpressionString() const pure nothrow @nogc
    {
        return expressionString;
    }

    override Any getValue() pure nothrow @nogc
    {
        return value;
    }
}
