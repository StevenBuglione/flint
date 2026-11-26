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
 * Ported from spring-framework v7.1.0: spring-expression/src/test/java/org/springframework/expression/spel/OperatorTests.java
 * Modified by the Flint authors.
 */
module flint.expression.operator_tests;

import flint.expression.spel : SpelMessage, SpelParseException;
import flint.expression.spel.standard : SpelExpressionParser;
import flint.java.lang : ArithmeticException;

@safe:

private void evaluate(T)(string expression, T expected)
{
    const value = (new SpelExpressionParser).parseExpression(expression).getValue();
    assert(value.typeName() == T.stringof, expression);
    assert(value.get!T == expected, expression);
}

@("multiplyDoubleDoubleGivesDouble") unittest
{
    evaluate("3.0d * 5.0d", 15.0);
}

@("mathOperatorsInChains") unittest
{
    evaluate("1+2+3", 6);
    evaluate("2*3*4", 24);
    evaluate("12-1-2", 9);
}

@("integerArithmetic") unittest
{
    evaluate("2 + 4", 6);
    evaluate("5 - 4", 1);
    evaluate("3 * 5", 15);
    evaluate("3.2d * 5", 16.0);
    evaluate("3 * 5f", 15f);
    evaluate("3 / 1", 3);
    evaluate("3 % 2", 1);
    foreach (op; ["mod", "mOd", "Mod", "MOD"])
        evaluate("3 " ~ op ~ " 2", 1);
}

@("parentheses, precedence, and numeric promotion")
unittest
{
    evaluate("2 * 3 + 4", 10);
    evaluate("2 + 3 * 4", 14);
    evaluate("(2 + 3) * 4", 20);
    evaluate("0x20 * 2L", 64L);
    evaluate("2147483647 + 1", int.min);
    evaluate("(0L - 9223372036854775807L - 1L) / -1L", long.min);
}

@("numeric evaluation is allocation-free")
unittest
{
    auto expression = (new SpelExpressionParser).parseRaw("1 + 2L * (3 - 1)");
    auto read = () nothrow @nogc => expression.evaluate();
    auto result = read();
    assert(result.ok() && result.value.typeName() == "long");
    assert(result.value.get!long == 5);
}

@("division by zero fails during evaluation")
unittest
{
    auto expression = (new SpelExpressionParser).parseExpression("1 / (2 - 2)");
    try
    {
        expression.getValue();
        assert(false, "division by zero succeeded");
    }
    catch (ArithmeticException expected)
    {
    }
}

@("nested expressions stay within the evaluator's stack")
unittest
{
    auto parser = new SpelExpressionParser;
    string expression = "1";
    int expected = 1;
    foreach (i; 0 .. 200)
    {
        expression = "1+2*(" ~ expression ~ ")";
        expected = cast(int)(1 + 2L * expected);
    }
    assert(parser.parseExpression(expression).getValue().get!int == expected);
    try
    {
        parser.parseExpression("(" ~ expression ~ ")");
        assert(false, "nesting beyond 200 parsed successfully");
    }
    catch (SpelParseException failure)
    {
        assert(failure.getMessageCode() == SpelMessage.MAX_EXPRESSION_NESTING_DEPTH_EXCEEDED);
    }
}
