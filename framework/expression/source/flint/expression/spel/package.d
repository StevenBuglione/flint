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
 * Ported from spring-framework v7.1.0: spring-expression/src/main/java/org/springframework/expression/spel/SpelMessage.java
 * Also from SpelParseException.java and SpelEvaluationException.java.
 * Modified by the Flint authors.
 */
module flint.expression.spel;

import flint.engine.aot.text : decimal;
import flint.expression : EvaluationException, ParseException;

@safe:

/// Stable identifiers for SpEL diagnostics.
enum SpelMessage
{
    TYPE_CONVERSION_ERROR = 1001,
    PROPERTY_OR_FIELD_NOT_READABLE_ON_NULL = 1007,
    PROPERTY_OR_FIELD_NOT_READABLE,
    CANNOT_INDEX_INTO_NULL_VALUE = 1012,
    EXCEPTION_DURING_PROPERTY_READ = 1021,
    ARRAY_INDEX_OUT_OF_BOUNDS = 1024,
    INDEXING_NOT_SUPPORTED_FOR_TYPE = 1027,
    NOT_AN_INTEGER = 1035,
    NOT_A_LONG,
    NOT_A_REAL = 1040,
    MORE_INPUT,
    OOD = 1044,
    NON_TERMINATING_DOUBLE_QUOTED_STRING,
    NON_TERMINATING_QUOTED_STRING,
    MISSING_LEADING_ZERO_FOR_NUMBER,
    REAL_CANNOT_BE_LONG,
    MAX_EXPRESSION_LENGTH_EXCEEDED = 1079,
    MAX_EXPRESSION_NESTING_DEPTH_EXCEEDED = 1087,
}

/// A parse exception with a SpEL diagnostic code.
class SpelParseException : ParseException
{
    private SpelMessage messageCode;

    package(flint.expression) this(string source, int position, SpelMessage code, string detail = null)
    {
        super(source, position, formatMessage(code, detail));
        messageCode = code;
    }

    SpelMessage getMessageCode() const pure nothrow @nogc
    {
        return messageCode;
    }
}

/// An evaluation exception with a SpEL diagnostic code.
class SpelEvaluationException : EvaluationException
{
    private SpelMessage messageCode;

    package(flint.expression) this(SpelMessage code, string detail)
    {
        super(formatMessage(code, detail));
        messageCode = code;
    }

    package(flint.expression) this(int position, SpelMessage code, string detail)
    {
        this(position, code, detail, null, null);
    }

    package(flint.expression) this(int position, SpelMessage code, string detail, string context, Throwable cause)
    {
        super(position, formatMessage(code, detail, context), cause);
        messageCode = code;
    }

    SpelMessage getMessageCode() const pure nothrow @nogc
    {
        return messageCode;
    }
}

private string formatMessage(SpelMessage code, string detail, string context = null)
{
    foreach (entry; diagnosticTexts)
        if (entry.code == code)
            return "EL" ~ decimal(cast(int) code) ~ "E: " ~ entry.prefix ~ detail ~ entry.between
                ~ context ~ entry.suffix;
    assert(0, "Missing SpEL diagnostic");
}

private struct DiagnosticText
{
    SpelMessage code;
    string prefix;
    string suffix;
    string between;
}

private immutable DiagnosticText[] diagnosticTexts = [
    DiagnosticText(SpelMessage.TYPE_CONVERSION_ERROR,
            "Type conversion problem, cannot convert from ",
            " to boolean"),
    DiagnosticText(SpelMessage.PROPERTY_OR_FIELD_NOT_READABLE_ON_NULL, "Property or field '",
            "' cannot be found on null"),
    DiagnosticText(SpelMessage.PROPERTY_OR_FIELD_NOT_READABLE, "Property or field '",
            "' - maybe not public or not valid?",
            "' cannot be found on object of type '"),
    DiagnosticText(SpelMessage.CANNOT_INDEX_INTO_NULL_VALUE, "Cannot index into a null value"),
    DiagnosticText(SpelMessage.EXCEPTION_DURING_PROPERTY_READ,
            "A problem occurred whilst attempting to access the property '", "'", "': '"),
    DiagnosticText(SpelMessage.ARRAY_INDEX_OUT_OF_BOUNDS, "The array has '", "' is invalid",
            "' elements, index '"),
    DiagnosticText(SpelMessage.INDEXING_NOT_SUPPORTED_FOR_TYPE, "Indexing into type '",
            "' is not supported"),
    DiagnosticText(SpelMessage.NOT_AN_INTEGER, "The value '", "' cannot be parsed as an int"),
    DiagnosticText(SpelMessage.NOT_A_LONG, "The value '", "' cannot be parsed as a long"),
    DiagnosticText(SpelMessage.NOT_A_REAL, "The value '", "' cannot be parsed as a double"),
    DiagnosticText(SpelMessage.MORE_INPUT,
            "After parsing a valid expression, there is still more data in the expression: '",
            "'"), DiagnosticText(SpelMessage.OOD,
            "Unexpectedly ran out of input"),
    DiagnosticText(SpelMessage.NON_TERMINATING_DOUBLE_QUOTED_STRING,
            "Cannot find terminating \" for string"),
    DiagnosticText(SpelMessage.NON_TERMINATING_QUOTED_STRING, "Cannot find terminating ' for string"),
    DiagnosticText(SpelMessage.MISSING_LEADING_ZERO_FOR_NUMBER,
            "A real number must be prefixed by zero, it cannot start with just '.'"),
    DiagnosticText(SpelMessage.REAL_CANNOT_BE_LONG,
            "Real number cannot be suffixed with a long (L or l) suffix"),
    DiagnosticText(SpelMessage.MAX_EXPRESSION_LENGTH_EXCEEDED,
            "SpEL expression is too long, exceeding the threshold of '", "' characters"),
    DiagnosticText(SpelMessage.MAX_EXPRESSION_NESTING_DEPTH_EXCEEDED,
            "SpEL expression nesting depth exceeds the threshold of "),
];
