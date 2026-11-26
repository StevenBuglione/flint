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
 * Ported from spring-framework v7.1.0: spring-expression/src/test/java/org/springframework/expression/spel/
 * ExpressionStateTests.java and ExpressionWithConversionTests.java, covering the conversion SPI directly.
 * Modified by the Flint authors.
 */
module flint.expression.type_converter_tests;

import flint.core.convert : ConversionFailedException, ConversionService, TypeDescriptor;
import flint.core.convert.support : GenericConversionService;
import flint.engine.aot.any : Any;
import flint.expression : TypeConverter;
import flint.expression.spel : SpelEvaluationException, SpelMessage;
import flint.expression.spel.support : StandardEvaluationContext, StandardTypeConverter;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.util.function_ : Supplier;

@safe:

@("an evaluation context retains its default and accepts a configured converter")
unittest
{
    auto context = new StandardEvaluationContext;
    const initial = context.getTypeConverter();
    assert(cast(const StandardTypeConverter) initial !is null);
    assert(context.getTypeConverter() is initial);
    assert((new StandardEvaluationContext).getTypeConverter() !is initial);

    auto registry = new GenericConversionService;
    registry.addConverter!(string, int)((string text) => cast(int) text.length);
    auto custom = new StandardTypeConverter(registry);
    context.setTypeConverter(custom);
    assert(context.getTypeConverter() is custom);
    const result = context.getTypeConverter().convertValue(Any.of("abc"),
            TypeDescriptor.valueOf!string, TypeDescriptor.valueOf!int);
    assert(result.get!int == 3);

    try
    {
        context.setTypeConverter(null);
        assert(false);
    }
    catch (IllegalArgumentException error)
    {
        assert(error.msg == "TypeConverter must not be null");
        assert(context.getTypeConverter() is custom);
    }
}

@("concurrent first context readers receive the same converter")
@system unittest
{
    import core.thread : Thread;

    auto context = new StandardEvaluationContext;
    TypeConverter first, second;
    auto reader = new Thread({ first = context.getTypeConverter(); });
    auto other = new Thread({ second = context.getTypeConverter(); });
    reader.start();
    other.start();
    reader.join();
    other.join();
    assert(first !is null && first is second);

    auto replacing = new StandardEvaluationContext;
    auto configured = new StandardTypeConverter(new GenericConversionService);
    auto initialReader = new Thread({ assert(replacing.getTypeConverter() !is null); });
    initialReader.start();
    replacing.setTypeConverter(configured);
    initialReader.join();
    assert(replacing.getTypeConverter() is configured);
}

@("default SpEL converter delegates scalar conversions")
unittest
{
    TypeConverter converter = new StandardTypeConverter;
    auto from = TypeDescriptor.valueOf!int;
    auto to = TypeDescriptor.valueOf!string;
    assert(converter.canConvert(from, to));
    assert(converter.convertValue(Any.of(34), from, to).get!string == "34");
    assert(converter.convertValue(Any.of(" 0x22 "), to, from).get!int == 34);
    assert(converter.convertValue(Any.init, null, to).isNull());
}

@("a configured service and suppliers follow each invocation")
unittest
{
    auto registry = new GenericConversionService;
    registry.addConverter!(string, int)((string value) => cast(int) value.length + 10);
    auto from = TypeDescriptor.valueOf!string;
    auto to = TypeDescriptor.valueOf!int;
    auto fixed = new StandardTypeConverter(registry);
    assert(fixed.convertValue(Any.of("xx"), from, to).get!int == 12);

    int calls;
    ConversionService delegate() @safe supply = () { ++calls; return registry; };
    auto converters = [
        new StandardTypeConverter(Supplier!ConversionService.of(supply)),
        new StandardTypeConverter(supply)
    ];
    assert(calls == 0);
    foreach (converter; converters)
    {
        const before = calls;
        assert(converter.canConvert(from, to));
        assert(converter.convertValue(Any.of("x"), from, to).get!int == 11);
        assert(calls == before + 2);
    }
}

@("SpEL conversion failures retain the core exception and type names")
unittest
{
    auto converter = new StandardTypeConverter;
    auto from = TypeDescriptor.valueOf!string;
    auto to = TypeDescriptor.valueOf!int;
    try
    {
        converter.convertValue(Any.of("x"), from, to);
        assert(false);
    }
    catch (SpelEvaluationException error)
    {
        assert(error.getMessageCode() == SpelMessage.TYPE_CONVERSION_ERROR);
        assert(error.getPosition() == 0 && error.getExpressionString() is null);
        assert(error.getSimpleMessage() == "EL1001E: Type conversion problem, cannot convert from string to int");
        auto conversion = cast(ConversionFailedException) error.getCause();
        assert(conversion !is null);
        assert(conversion.getSourceType() is from && conversion.getTargetType() is to);
    }
}

@("SpEL converter constructors reject null services and suppliers")
unittest
{
    try
    {
        new StandardTypeConverter(cast(ConversionService) null);
        assert(false);
    }
    catch (IllegalArgumentException error)
    {
        assert(error.msg == "ConversionService must not be null");
    }
    try
    {
        new StandardTypeConverter(cast(Supplier!ConversionService) null);
        assert(false);
    }
    catch (IllegalArgumentException error)
    {
        assert(error.msg == "Supplier must not be null");
    }
    auto converter = new StandardTypeConverter(() => cast(ConversionService) null);
    try
    {
        converter.canConvert(null, TypeDescriptor.valueOf!string);
        assert(false);
    }
    catch (NullPointerException)
    {
    }
}
