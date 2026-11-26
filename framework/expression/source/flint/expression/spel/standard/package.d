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

import flint.arena : Result, Status;
import flint.engine.aot.any : Any;
import flint.expression : EvaluationException, Expression, ExpressionParser;
import flint.expression.spel : SpelEvaluationException, SpelMessage;
import flint.expression.spel.standard.arithmetic : ArithmeticExpression, parseArithmetic;
import flint.expression.spel.standard.literal : utf16Length;
import flint.java.lang : ArithmeticException;

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
        return new SpelExpression(expressionString, parseArithmetic(expressionString));
    }
}

/// A parsed SpEL expression that can be evaluated repeatedly.
class SpelExpression : Expression
{
    private string expressionString;
    private ArithmeticExpression expression;

    package(flint.expression.spel.standard) this(string expressionString, ArithmeticExpression expression)
    {
        this.expressionString = expressionString;
        this.expression = expression;
    }

    override string getExpressionString() const pure nothrow @nogc
    {
        return expressionString;
    }

    /// Evaluate the parsed expression. Throws `ArithmeticException` on integral division or remainder by zero.
    override Any getValue()
    {
        auto result = evaluate();
        if (result.ok())
            return result.value;
        if (result.error.code == Status.invalidArgument)
            throw new ArithmeticException(result.error.message);
        throw new EvaluationException(result.error.message);
    }

    package(flint.expression) Result!Any evaluate() pure nothrow @nogc
    {
        return expression.evaluate();
    }
}
