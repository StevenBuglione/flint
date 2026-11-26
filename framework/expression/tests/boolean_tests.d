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
 * spring-expression/src/test/java/org/springframework/expression/spel/BooleanExpressionTests.java
 * Modified by the Flint authors.
 */
module flint.expression.boolean_tests;

import flint.expression.spel : SpelEvaluationException, SpelMessage;
import flint.expression.spel.standard : SpelExpressionParser;
import flint.expression.spel.support : StandardEvaluationContext;
import flint.java.lang : ArithmeticException;

@safe:

private void evaluate(string source, bool expected)
{
    auto parsed = (new SpelExpressionParser).parseRaw(source);
    auto read = () nothrow @nogc => parsed.evaluate();
    const result = read();
    assert(result.ok() && result.value.typeName() == "bool", source);
    assert(result.value.get!bool == expected, source);
}

@("booleanTrue") unittest
{
    evaluate("true", true);
}

@("booleanFalse") unittest
{
    evaluate("false", false);
}

@("or") unittest
{
    evaluate("false or false", false);
    evaluate("false or true", true);
    evaluate("true or false", true);
    evaluate("true or true", true);
}

@("and") unittest
{
    evaluate("false and false", false);
    evaluate("false and true", false);
    evaluate("true and false", false);
    evaluate("true and true", true);
}

@("not") unittest
{
    evaluate("!false", true);
    evaluate("!true", false);
    evaluate("not false", true);
    evaluate("NoT true", false);
}

@("combinations01") unittest
{
    evaluate("false and false or true", true);
    evaluate("true and false or true", true);
    evaluate("true and false or false", false);
}

@("writability") unittest
{
    auto parser = new SpelExpressionParser;
    auto context = new StandardEvaluationContext;
    foreach (source; ["true and true", "true or true", "!false"])
    {
        auto expression = parser.parseExpression(source);
        assert(expression.getValue(context).get!bool);
        assert(!expression.isWritable(context));
    }
}

@("booleanErrors01") unittest
{
    auto parser = new SpelExpressionParser;
    foreach (index, source; [
        "1.0 or false", "false or 39.4", "true and 'hello'", " 'hello' and 'goodbye'", "!35.2",
        "! 'foob'", "!null", "'😀' == '😀' and 1"
    ])
    {
        const int[] positions = [0, 9, 9, 1, 1, 2, 1, 17];
        auto expression = parser.parseExpression(source);
        try
        {
            expression.getValue();
            assert(false, source);
        }
        catch (SpelEvaluationException error)
        {
            assert(error.getMessageCode() == SpelMessage.TYPE_CONVERSION_ERROR, source);
            assert(error.getPosition() == positions[index], source);
        }
    }
}

@("boolean expressions short-circuit but check any operand they use")
unittest
{
    evaluate("false && (1 / 0 > 0)", false);
    evaluate("true || (1 / 0 > 0)", true);
    evaluate("true OR false AnD false", true);
    evaluate("not not true && 1 < 2", true);
    evaluate("' yes ' and not 'Off'", true);
    auto expression = (new SpelExpressionParser).parseRaw("true && (1 / 0 > 0)");
    try
    {
        expression.getValue();
        assert(false);
    }
    catch (ArithmeticException error)
    {
        assert(error.msg == "/ by zero");
    }
}
