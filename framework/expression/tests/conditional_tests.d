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
 * spring-expression/src/test/java/org/springframework/expression/spel/EvaluationTests.java
 * Also from SpelReproTests.java.
 * Modified by the Flint authors.
 */
module flint.expression.conditional_tests;

import flint.engine.aot.any : Any;
import flint.expression.spel : SpelEvaluationException, SpelMessage;
import flint.expression.spel.standard : SpelExpressionParser;
import flint.expression.spel.support : StandardEvaluationContext;

@safe:

private void evaluate(string source, Any expected)
{
    auto expression = (new SpelExpressionParser).parseRaw(source);
    auto read = () nothrow @nogc => expression.evaluate();
    const result = read();
    assert(result.ok() && result.value == expected, source);
}

@("ternaryExpressionWithNullConditionType") unittest
{
    auto expression = (new SpelExpressionParser).parseRaw("null ? 0 : 1");
    try
    {
        expression.getValue();
        assert(false);
    }
    catch (SpelEvaluationException error)
    {
        assert(error.getMessageCode() == SpelMessage.TYPE_CONVERSION_ERROR && error.getPosition() == 0);
    }
}

@("ternaryExpressionWithInvalidConditionType") unittest
{
    auto expression = (new SpelExpressionParser).parseRaw("'hello' ? 1 : 2");
    try
    {
        expression.getValue();
        assert(false);
    }
    catch (SpelEvaluationException error)
    {
        assert(error.getMessageCode() == SpelMessage.TYPE_CONVERSION_ERROR && error.getPosition() == 0);
    }
}

@("ternaryExpressionIsNotWritable") unittest
{
    auto expression = (new SpelExpressionParser).parseExpression("1 > 2 ? 3 : 4");
    assert(!expression.isWritable(new StandardEvaluationContext));
}

@("ternaryExpressionsWithImplicitGrouping") unittest
{
    evaluate("4 % 2 == 0 ? 2 : 3 * 10", Any.of(2));
    evaluate("4 % 2 == 1 ? 2 : 3 * 10", Any.of(30));
}

@("ternaryExpressionsWithExplicitGrouping") unittest
{
    evaluate("((4 % 2 == 0) ? 2 : 1) * 10", Any.of(20));
}

@("ternary evaluates one branch and preserves the selected type")
unittest
{
    evaluate("true ? 1 : 2L", Any.of(1));
    evaluate("false ? 1 : true ? 2L : 3.0", Any.of(2L));
    evaluate("true ? 'chosen' : 1 / 0", Any.of("chosen"));
    evaluate("false ? 1 / 0 : 'other'", Any.of("other"));
    evaluate("2 > 4 ? (3 > 2 ? true : false) : (5 < 3 ? true : false)", Any.of(false));
}

@("elvis falls back only for null and empty strings")
unittest
{
    evaluate("'Andy' ?: 'Dave'", Any.of("Andy"));
    evaluate("null ?: 'Dave'", Any.of("Dave"));
    evaluate("'' ?: 'Dave'", Any.of("Dave"));
    evaluate("3 ?: 1 / 0", Any.of(3));
    evaluate("(2 * 3) ?: 1 * 10", Any.of(6));
    evaluate("null ?: 2 * 10", Any.of(20));
    evaluate("(null ?: 1) * 10", Any.of(10));
    evaluate("false ?: true", Any.of(false));
    evaluate("0 ?: 10", Any.of(0));
    evaluate("null ?: '' ?: 'tail'", Any.of("tail"));
}

@("elvis_SPR7209_2") unittest
{
    evaluate("?:'default'", Any.of("default"));
    evaluate("\"\"?:'default'", Any.of("default"));
    evaluate("''?:'default'", Any.of("default"));
}
