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
import flint.expression.spel : SpelEvaluationException, SpelMessage, SpelParseException;
import flint.expression.spel.standard : SpelExpressionParser;
import flint.expression.spel.support : StandardEvaluationContext;
import flint.java.lang : IllegalStateException, IndexOutOfBoundsException;

@safe:

private final class ArrayRoot
{
    private Any values;
    private int offset;
    private int reads;

    Any getProperty()
    {
        return values;
    }

    int getOffset()
    {
        ++reads;
        return offset;
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
    context.getPropertyAccessors();
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

@("nullSafeIndexIntoString") unittest
{
    auto root = new ArrayRoot;
    auto context = contextFor(root);
    auto expression = (new SpelExpressionParser).parseExpression("property?.[0]");
    assert(expression.getValue(context).isNull());
    root.values = Any.of("XYZ");
    assert(expression.getValue(context).get!string == "X");
}

@("string indexes preserve BMP characters and UTF-16 offsets")
unittest
{
    auto parser = new SpelExpressionParser;
    const text = "Aé中";
    const character = parser.parseExpression("#root[1]").getValue(Any.of(text)).get!string;
    assert(character == "é" && character.ptr is text[1 .. 3].ptr);
    assert(parser.parseExpression("'Aé中'[1 + 1]").getValue().get!string == "中");
    assert(parser.parseExpression("'A😀Z'[1]").getValue().get!string == "\uFFFD");
    assert(parser.parseExpression("'A😀Z'[2]").getValue().get!string == "\uFFFD");
    assert(parser.parseExpression("'A😀Z'[3]").getValue().get!string == "Z");

    try
    {
        parser.parseExpression("'é😀'[3]").getValue();
        assert(false);
    }
    catch (SpelEvaluationException error)
    {
        assert(error.getPosition() == 5);
        assert(error.getMessageCode() == SpelMessage.STRING_INDEX_OUT_OF_BOUNDS);
        assert(error.getSimpleMessage() == "EL1026E: The string has '3' characters, index '3' is invalid");
    }
}

@("computed array indexes use the original root")
unittest
{
    auto root = new ArrayRoot;
    root.values = Any.of([[4, 5], [6, 7]]);
    root.offset = 1;
    auto context = contextFor(root);
    context.setVariable("column", Any.of(0));
    auto parser = new SpelExpressionParser;
    auto expression = parser.parseExpression("property[#this.offset][#column + offset]");
    assert(expression.getValue(context).get!int == 7);
    assert(root.reads == 2);

    auto explicitRoot = new ArrayRoot;
    explicitRoot.values = Any.of([[10, 11], [12, 13]]);
    assert(expression.getValue(context, Any.of(explicitRoot)).get!int == 10);
    assert(root.reads == 2 && explicitRoot.reads == 2);
}

@("null-safe and untaken array hops skip computed indexes")
unittest
{
    auto root = new ArrayRoot;
    auto context = contextFor(root);
    auto parser = new SpelExpressionParser;
    auto safe = parser.parseExpression("property?.[offset + 1]");
    assert(safe.getValue(context).isNull());
    assert(root.reads == 0);

    root.values = Any.of([2, 3]);
    assert(parser.parseExpression("false ? property[offset] : 4").getValue(context).get!int == 4);
    assert(root.reads == 0);
    assert(safe.getValue(context).get!int == 3);
    assert(root.reads == 1);
}

@("nested array index plans preserve pending arithmetic operands")
unittest
{
    auto root = new ArrayRoot;
    root.values = Any.of([0, 0]);
    auto context = contextFor(root);
    auto parser = new SpelExpressionParser;
    string source = "0";
    foreach (_; 0 .. 200)
        source = "1 + 2 * property[" ~ source ~ "]";
    assert(parser.parseExpression(source).getValue(context).get!int == 1);
    try
    {
        parser.parseExpression("property[" ~ source ~ "]");
        assert(false);
    }
    catch (SpelParseException error)
    {
        assert(error.getMessageCode() == SpelMessage.MAX_EXPRESSION_NESTING_DEPTH_EXCEEDED);
    }
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
    check("property[true]", SpelMessage.TYPE_CONVERSION_ERROR, 8,
            "EL1001E: Type conversion problem, cannot convert from bool to int");
    try
    {
        parser.parseExpression("property[null]").getValue(context);
        assert(false);
    }
    catch (IllegalStateException error)
    {
        assert(error.msg == "No index");
    }
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
    root.values = Any.of("");
    check("property[0]", SpelMessage.STRING_INDEX_OUT_OF_BOUNDS, 8,
            "EL1026E: The string has '0' characters, index '0' is invalid");
}
