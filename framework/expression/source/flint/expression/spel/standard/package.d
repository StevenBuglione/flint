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

import flint.arena : Error, Result, Status;
import flint.engine.aot.any : Any;
import flint.expression : EvaluationContext, EvaluationException, Expression, ExpressionParser;
import flint.expression.spel : SpelEvaluationException, SpelMessage;
import flint.expression.spel.context : EvaluationContextAccess;
import flint.expression.spel.standard.arithmetic : ArithmeticExpression, isRootReference, parseArithmetic;
import flint.expression.spel.standard.literal : utf16Length;
import flint.expression.spel.standard.property : PropertyStep, readPropertyPath;
import flint.java.lang : ArithmeticException, IllegalArgumentException;

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
        return evaluateWithContext(null, Any.init, true);
    }

    override Any getValue(Any rootObject)
    {
        return evaluateWithContext(null, rootObject, false);
    }

    override Any getValue(EvaluationContext context)
    {
        requireContext(context);
        return evaluateWithContext(context, Any.init, true);
    }

    override Any getValue(EvaluationContext context, Any rootObject)
    {
        requireContext(context);
        return evaluateWithContext(context, rootObject, false);
    }

    override bool isWritable(EvaluationContext context)
    {
        requireContext(context);
        if (expression.hasProperties())
            return false;
        auto bounded = cast(EvaluationContextAccess) context;
        if (bounded is null || !bounded.isStandardContext())
            context.getRootObject();
        return expression.variable !is null && !isRootReference(expression.variable);
    }

    private Any evaluateWithContext(EvaluationContext context, Any rootObject, bool useContextRoot)
    {
        auto standard = cast(EvaluationContextAccess) context;
        // Guard virtual behavior: a subclass may override either lookup.
        if (!expression.hasProperties() && (context is null || (standard !is null && standard.isStandardContext())))
            return unwrap(evaluate(standard, rootObject, useContextRoot));
        if (useContextRoot && context !is null)
            rootObject = context.getRootObject().getValue();
        return unwrap(expression.evaluate(rootObject, (string name, scope const(PropertyStep)[] path) {
                const useRoot = name is null || isRootReference(name);
                auto receiver = useRoot ? rootObject : context is null ? Any.init : context.lookupVariable(name);
                return path.length ? readPropertyPath(expressionString, path, receiver, context) : receiver;
            }));
    }

    private Any unwrap(Result!Any result)
    {
        if (result.ok())
            return result.value;
        if (result.error.code == Status.invalidArgument)
            throw new ArithmeticException(result.error.message);
        if (result.error.code == Status.conflict)
        {
            const position = cast(int) utf16Length(expressionString[0 .. result.error.offset]);
            throw new SpelEvaluationException(position, SpelMessage.TYPE_CONVERSION_ERROR, result.error.message);
        }
        throw new EvaluationException(result.error.message);
    }

    // Call with the exact StandardEvaluationContext, or null for the empty default context.
    package(flint.expression) Result!Any evaluate(EvaluationContextAccess context = null,
            Any rootObject = Any.init, bool useContextRoot = true) nothrow @nogc
    {
        if (expression.hasProperties())
            return Result!Any(Any.init, Error(Status.unsupported, "Property reads use the SpEL API boundary"));
        if (useContextRoot && expression.readsRoot && context !is null)
            rootObject = context.readRootObject().getValue();
        return expression.evaluate(rootObject, (string name,
                scope const(PropertyStep)[]) nothrow @nogc => context is null ? Any.init : context.readVariable(name));
    }
}

private void requireContext(EvaluationContext context)
{
    if (context is null)
        throw new IllegalArgumentException("EvaluationContext must not be null");
}
