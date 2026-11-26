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
 * spring-expression/src/test/java/org/springframework/expression/spel/OperatorTests.java
 * Modified by the Flint authors.
 */
module flint.expression.comparison_tests;

import flint.expression.spel : SpelMessage, SpelParseException;
import flint.expression.spel.standard : SpelExpressionParser;

@safe:

private void evaluate(string source, bool expected)
{
    auto expression = (new SpelExpressionParser).parseRaw(source);
    auto read = () nothrow @nogc => expression.evaluate();
    const result = read();
    assert(result.ok() && result.value.typeName() == "bool", source);
    assert(result.value.get!bool == expected, source);
}

@("strings") unittest
{
    evaluate("'abc' == 'abc'", true);
    evaluate("'abc' == 'def'", false);
    evaluate("'abc' != 'abc'", false);
    evaluate("'abc' != 'def'", true);
}

@("comparison uses Java numeric promotion")
unittest
{
    evaluate("1 + 2 * 3 == 7L", true);
    evaluate("2.5 gt 2", true);
    evaluate("2.5 Ge 2.5f", true);
    evaluate("2.5 LT 3", true);
    evaluate("2.5 le 2L", false);
    evaluate("1L ne 1.0f", false);
    evaluate("9007199254740993L > 9007199254740992L", true);
    evaluate("0.0 == -0.0", true);
    evaluate("0.0 / 0.0 == 0.0 / 0.0", false);
    evaluate("0.0 / 0.0 >= 0.0", false);
    evaluate("0.0 / 0.0 != 0.0", true);
}

@("strings are ordered by Java UTF-16 code units")
unittest
{
    evaluate("'a' < 'ab'", true);
    evaluate("'😀' < '\uE000'", true);
    evaluate("'😀' > '𐐀'", true);
    evaluate("('this' == 'this') eq true", true);
}

@("null sorts before every scalar")
unittest
{
    evaluate("null == null", true);
    evaluate("null < 0", true);
    evaluate("'' > null", true);
    evaluate("null != false", true);
    evaluate("true >= false", true);
    evaluate("'1' eq 1", false);
}

@("relational operators do not chain")
unittest
{
    auto parser = new SpelExpressionParser;
    try
    {
        parser.parseRaw("1 < 2 == true");
        assert(false, "A second comparison requires grouping");
    }
    catch (SpelParseException error)
    {
        assert(error.getMessageCode() == SpelMessage.MORE_INPUT && error.getPosition() == 6);
    }
}
