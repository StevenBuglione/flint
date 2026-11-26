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
 * Ported from spring-framework v7.1.0, spring-expression/src/test/java/org/springframework/expression/spel/LiteralTests.java
 * Modified by the Flint authors.
 */
module flint.expression.literal_tests;

import flint.expression.spel : SpelMessage, SpelParseException;
import flint.expression.spel.standard : SpelExpressionParser;

@safe:

private void evaluate(T)(string expression, T expected)
{
    auto parsed = (new SpelExpressionParser).parseExpression(expression);
    assert(parsed.getExpressionString() == expression);
    const result = parsed.getValue();
    assert(result.typeName() == T.stringof, expression);
    assert(result.get!T == expected, expression);
}

@("booleans") unittest
{
    evaluate("false", false);
    evaluate("true", true);
}

@("strings") unittest
{
    evaluate("'hello'", "hello");
    evaluate("'joe bloggs'", "joe bloggs");
    evaluate("'Hello World'", "Hello World");
}

@("stringsContainingQuotes") unittest
{
    evaluate("'Tony''s Pizza'", "Tony's Pizza");
    evaluate("'Tony\\r''s Pizza'", "Tony\\r's Pizza");
    evaluate("\"Hello World\"", "Hello World");
    evaluate("\"Hello ' World\"", "Hello ' World");
}

@("integers") unittest
{
    evaluate("1", 1);
    evaluate("1415", 1415);
}

@("longs") unittest
{
    evaluate("1L", 1L);
    evaluate("1415L", 1415L);
}

@("signedIntegers") unittest
{
    evaluate("-1", -1);
    evaluate("-0xa", -10);
}

@("signedLongs") unittest
{
    evaluate("-1L", -1L);
    evaluate("-0x20l", -32L);
}

@("hexIntegers") unittest
{
    evaluate("0x7FFFF", 524_287);
    evaluate("0X7FFFF", 524_287);
}

@("hexLongs") unittest
{
    evaluate("0X7FFFFl", 524_287L);
    evaluate("0x7FFFFL", 524_287L);
    evaluate("0xCAFEBABEL", 3_405_691_582L);
}

@("floats") unittest
{
    evaluate("1.25f", 1.25f);
    evaluate("2.5f", 2.5f);
    evaluate("-3.5f", -3.5f);
    evaluate("1.25F", 1.25f);
    evaluate("2.5F", 2.5f);
    evaluate("-3.5F", -3.5f);
}

@("doubles") unittest
{
    foreach (suffix; ["", "d", "D"])
    {
        evaluate("1.25" ~ suffix, 1.25);
        evaluate("2.99" ~ suffix, 2.99);
        evaluate("-3.141" ~ suffix, -3.141);
    }
}

@("doublesUsingExponents") unittest
{
    evaluate("6.0221415E+23", 6.0221415E23);
    evaluate("6.0221415e+23", 6.0221415E23);
    evaluate("6.0221415E+23d", 6.0221415E23);
    evaluate("6.0221415e+23D", 6.0221415E23);
    evaluate("6E2f", 6E2f);
}

@("doublesUsingExponentsWithInvalidInput") unittest
{
    enum message = "EL1041E: After parsing a valid expression, there is still more data in the expression: ";
    expectParseError("6.1e23e22", SpelMessage.MORE_INPUT, 6, message ~ "'e22'");
    expectParseError("6.1f23e22", SpelMessage.MORE_INPUT, 4, message ~ "'23e22'");
}

@("nullLiteral") unittest
{
    assert((new SpelExpressionParser).parseExpression("null").getValue().isNull());
}

@("parsed literals can be read without allocation")
unittest
{
    auto parsed = (new SpelExpressionParser).parseRaw("  'ひ'  ");
    auto read = () nothrow @nogc => parsed.evaluate();
    auto value = read();
    assert(value.ok() && value.value.get!string == "ひ");
    assert(!(new SpelExpressionParser).parseRaw("''").getValue().isNull());
}

@("parse positions use Java string indexing")
unittest
{
    expectParseError("'🌱' 42", SpelMessage.MORE_INPUT, 5);
    expectParseError("2147483648", SpelMessage.NOT_AN_INTEGER, 0);
    expectParseError("9223372036854775808L", SpelMessage.NOT_A_LONG, 0);
    expectParseError("'broken", SpelMessage.NON_TERMINATING_QUOTED_STRING, 0);
    expectParseError("\"broken", SpelMessage.NON_TERMINATING_DOUBLE_QUOTED_STRING, 0);
}

private void expectParseError(string expression, SpelMessage code, int position, string message = null)
{
    try
    {
        (new SpelExpressionParser).parseRaw(expression);
        assert(false, expression);
    }
    catch (SpelParseException failure)
    {
        assert(failure.getExpressionString() == expression);
        assert(failure.getMessageCode() == code);
        assert(failure.getPosition() == position);
        if (message !is null)
            assert(failure.getSimpleMessage() == message);
    }
}
