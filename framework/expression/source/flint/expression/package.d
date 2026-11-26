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
 * Ported from spring-framework v7.1.0: spring-expression/src/main/java/org/springframework/expression/Expression.java
 * Also from ExpressionParser.java, ExpressionException.java, ParseException.java and EvaluationException.java.
 * Modified by the Flint authors.
 */
module flint.expression;

import flint.engine.aot.any : Any;
import flint.engine.aot.text : decimal;
import flint.java.lang : RuntimeException;

@safe:

/// A parsed expression that can be evaluated repeatedly.
interface Expression
{
    /// The original expression text.
    string getExpressionString();

    /// Evaluate using the expression's default context.
    Any getValue();
}

/// A parser of expression source text.
interface ExpressionParser
{
    /// Parse an expression for later evaluation.
    Expression parseExpression(string expressionString);
}

/// An expression error, including its source and position when available.
class ExpressionException : RuntimeException
{
    private string expressionString;
    private string simpleMessage;
    private int position;

    /// Create an exception with a message.
    this(string message)
    {
        this(null, 0, message);
    }

    /// Create an exception with a message and cause.
    this(string message, Throwable cause)
    {
        this(null, 0, message, cause);
    }

    /// Include the expression text when the error position is unknown.
    this(string expressionString, string message)
    {
        this(expressionString, -1, message);
    }

    /// Include the expression text and its UTF-16 error position.
    this(string expressionString, int position, string message)
    {
        this(expressionString, position, message, null);
    }

    /// Include an error position in UTF-16 code units.
    this(int position, string message)
    {
        this(null, position, message);
    }

    /// Include an error position and cause.
    this(int position, string message, Throwable cause)
    {
        this(null, position, message, cause);
    }

    private this(string expressionString, int position, string message, Throwable cause)
    {
        this.expressionString = expressionString;
        this.position = position;
        simpleMessage = message;
        super(detailedMessage(expressionString, position, message), cause);
    }

    /// The full expression text, when available.
    final string getExpressionString() const pure nothrow @nogc
    {
        return expressionString;
    }

    /// The offset in UTF-16 code units. A negative position means the offset is unknown.
    final int getPosition() const pure nothrow @nogc
    {
        return position;
    }

    /// The message without the source and position.
    string getSimpleMessage() const pure nothrow @nogc
    {
        return simpleMessage;
    }

    /// The message with any available source and position.
    string toDetailedString() const pure nothrow @nogc
    {
        return msg;
    }
}

private string detailedMessage(string source, int position, string message)
{
    if (source is null)
        return message;
    const location = position >= 0 ? " @" ~ decimal(position) : "";
    return "Expression [" ~ source ~ "]" ~ location ~ ": " ~ message;
}

/// An error while parsing an expression.
class ParseException : ExpressionException
{
    /// Report a parse error in the given expression.
    this(string expressionString, int position, string message)
    {
        super(expressionString, position, message);
    }

    /// Report a parse error position and its cause.
    this(int position, string message, Throwable cause)
    {
        super(position, message, cause);
    }

    /// Report a parse error position.
    this(int position, string message)
    {
        super(position, message);
    }
}

/// An error while evaluating an expression.
class EvaluationException : ExpressionException
{
    /// Report an error during evaluation.
    this(string message)
    {
        super(message);
    }
}
