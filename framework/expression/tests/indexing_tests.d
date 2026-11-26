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
 * Ported from spring-framework v7.1.0: spring-expression/src/test/java/org/springframework/expression/spel/IndexingTests.java
 * Modified by the Flint authors.
 */
module flint.expression.indexing_tests;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;
import flint.expression.spel : SpelEvaluationException, SpelMessage;
import flint.expression.spel.standard : SpelExpressionParser;
import flint.expression.spel.support : StandardEvaluationContext;
import flint.java.lang : IndexOutOfBoundsException;

@safe:

private final class ArrayRoot
{
    private Any values;

    Any getProperty()
    {
        return values;
    }
}

private StandardEvaluationContext contextFor(ArrayRoot root)
{
    auto descriptors = new DescriptorTable;
    descriptors.add(descriptorOf!ArrayRoot);
    descriptors.add(descriptorOf!(int[]));
    descriptors.add(descriptorOf!(int[][]));
    auto context = new StandardEvaluationContext(Any.of(root));
    context.setDescriptorTable(descriptors);
    return context;
}

@("indexIntoArrays") unittest
{
    auto root = new ArrayRoot;
    auto context = contextFor(root);
    auto parser = new SpelExpressionParser;
    root.values = Any.of([1, 2, 3, 4]);
    assert(parser.parseExpression("property[2]").getValue(context).get!int == 3);

    root.values = Any.of([[1, 2], [3, 4]]);
    assert(parser.parseExpression("property[0]").getValue(context).get!(int[]) == [1, 2]);
    assert(parser.parseExpression("property[1][1]").getValue(context).get!int == 4);
}

@("array indexes work on roots and variables inside scalar expressions")
unittest
{
    auto context = contextFor(new ArrayRoot);
    auto numbers = Any.of([2, 3]);
    context.setRootObject(numbers);
    context.setVariable("numbers", numbers);
    auto parser = new SpelExpressionParser;
    assert(parser.parseExpression("[0] + #numbers[1]").getValue(context).get!int == 5);
    assert(parser.parseExpression("false ? #root[9] : #root[1]").getValue(context).get!int == 3);
}

@("nullSafeIndexIntoArray") unittest
{
    auto root = new ArrayRoot;
    auto context = contextFor(root);
    auto expression = (new SpelExpressionParser).parseExpression("property?.[0]");
    assert(expression.getValue(context).isNull());
    root.values = Any.of([42]);
    assert(expression.getValue(context).get!int == 42);
}

@("array indexes check the receiver and bounds before invoking the descriptor")
unittest
{
    auto root = new ArrayRoot;
    auto context = contextFor(root);
    auto parser = new SpelExpressionParser;

    void check(string source, SpelMessage code, int position, string message)
    {
        try
        {
            parser.parseExpression(source).getValue(context);
            assert(false, source);
        }
        catch (SpelEvaluationException error)
        {
            assert(error.getMessageCode() == code && error.getPosition() == position, source);
            assert(error.getSimpleMessage() == message, source);
        }
    }

    check("property[0]", SpelMessage.CANNOT_INDEX_INTO_NULL_VALUE, 8, "EL1012E: Cannot index into a null value");
    root.values = Any.of([1]);
    check("property[1]", SpelMessage.ARRAY_INDEX_OUT_OF_BOUNDS, 8,
            "EL1024E: The array has '1' elements, index '1' is invalid");
    try
    {
        parser.parseExpression("property[-1]").getValue(context);
        assert(false);
    }
    catch (IndexOutOfBoundsException)
    {
    }
    root.values = Any.of(1);
    check("property[0]", SpelMessage.INDEXING_NOT_SUPPORTED_FOR_TYPE, 8,
            "EL1027E: Indexing into type 'int' is not supported");
}
