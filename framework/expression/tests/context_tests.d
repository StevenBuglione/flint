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
 * spring-expression/src/test/java/org/springframework/expression/spel/VariableAndFunctionTests.java
 * Also from LiteralTests.java.
 * Modified by the Flint authors.
 */
module flint.expression.context_tests;

import flint.engine.aot.any : Any;
import flint.expression : EvaluationContext, EvaluationException, TypedValue;
import flint.expression.spel : SpelParseException;
import flint.expression.spel.standard : SpelExpressionParser;
import flint.expression.spel.support : StandardEvaluationContext;
import flint.java.lang : IllegalArgumentException, IllegalStateException;

@safe:

@("a parsed variable reads the current context")
unittest
{
    auto context = new StandardEvaluationContext;
    auto expression = (new SpelExpressionParser).parseExpression("#answer");
    assert(expression.getValue(context).isNull());
    assert(expression.isWritable(context));

    context.setVariable("answer", Any.of(42));
    assert(expression.getValue(context).typeName() == "int");
    assert(expression.getValue(context).get!int == 42);
    context.setVariable("answer", Any.of("different"));
    assert(expression.getValue(context).get!string == "different");

    context.setVariable("answer", Any.init);
    context.setVariable(null, Any.of(7));
    assert(expression.getValue(context).isNull());
    assert(expression.getValue().isNull());
}

@("explicit roots override context roots")
unittest
{
    auto context = new StandardEvaluationContext(Any.of("Tesla"));
    auto parser = new SpelExpressionParser;
    foreach (name; ["#root", "(#this)"])
    {
        auto expression = parser.parseExpression(name);
        assert(!expression.isWritable(context));
        assert(expression.getValue(context).get!string == "Tesla");
        assert(expression.getValue(context, Any.of(17)).get!int == 17);
        assert(expression.getValue(context, Any.init).isNull());
        assert(expression.getValue(Any.of("explicit")).get!string == "explicit");
        assert(expression.getValue().isNull());
    }

    auto root = context.getRootObject();
    context.setRootObject(Any.init);
    assert(root.getValue().get!string == "Tesla");
    assert(context.getRootObject() == TypedValue.NULL);
}

@("notWritable") unittest
{
    auto parser = new SpelExpressionParser;
    auto context = new StandardEvaluationContext;
    foreach (source; ["37", "37L", "true"])
        assert(!parser.parseRaw(source).isWritable(context));
}

@("context lookups keep Java identifier spelling")
unittest
{
    auto context = new StandardEvaluationContext;
    auto parser = new SpelExpressionParser;
    foreach (name; ["answer", "Answer", "résultat2", "_a", "$a"])
    {
        context.setVariable(name, Any.of(name));
        assert(parser.parseExpression("#" ~ name).getValue(context).get!string == name);
    }
}

@("an incomplete variable reports a parse error")
unittest
{
    auto parser = new SpelExpressionParser;
    foreach (source; ["#", "# ", "#7"])
    {
        try
        {
            parser.parseExpression(source);
            assert(false, source);
        }
        catch (SpelParseException error)
        {
            assert(error.getPosition() >= 1, source);
        }
    }
}

@("custom contexts retain virtual lookups and may throw")
unittest
{
    static class CustomContext : StandardEvaluationContext
    {
        override Any lookupVariable(string name)
        {
            if (name == "invalid")
                throw new IllegalStateException("custom lookup");
            return Any.of(name ~ "-custom");
        }

        override TypedValue getRootObject()
        {
            return TypedValue(Any.of("root" ~ "-custom"));
        }
    }

    auto parser = new SpelExpressionParser;
    EvaluationContext custom = new CustomContext;
    auto variable = parser.parseRaw("#answer");
    assert(variable.getValue(custom).get!string == "answer-custom");
    assert(parser.parseRaw("#root").getValue(custom).get!string == "root-custom");
    try
    {
        parser.parseRaw("#invalid").getValue(custom);
        assert(false, "The custom exception must propagate");
    }
    catch (IllegalStateException error)
    {
        assert(error.msg == "custom lookup");
    }

    try
    {
        variable.getValue(cast(EvaluationContext) null);
        assert(false, "The context argument is required");
    }
    catch (IllegalArgumentException error)
    {
        assert(error.msg == "EvaluationContext must not be null");
    }
}

@("a shared context publishes complete root and variable values")
@system unittest
{
    import core.thread : Thread;

    auto context = new StandardEvaluationContext(Any.of("before"));
    context.setVariable("value", Any.of(31));
    auto parser = new SpelExpressionParser;
    auto variable = parser.parseRaw("#value");
    auto root = parser.parseRaw("#root");

    auto writer = new Thread({
        foreach (i; 0 .. 2_000)
        {
            context.setVariable("value", i % 2 ? Any.of(31) : Any.of("after"));
            context.setRootObject(i % 2 ? Any.of("before") : Any.of(47));
        }
    });
    auto otherWriter = new Thread({
        foreach (i; 0 .. 2_000)
        {
            context.setVariable("other", Any.of(i));
            context.setVariable("other", Any.init);
        }
    });
    writer.start();
    otherWriter.start();
    foreach (i; 0 .. 8_000)
    {
        auto read = () nothrow @nogc => variable.evaluate(context);
        auto value = read();
        assert(value.ok() && (value.value == Any.of(31) || value.value == Any.of("after")));
        auto readRoot = () nothrow @nogc => root.evaluate(context);
        auto current = readRoot();
        assert(current.ok() && (current.value == Any.of("before") || current.value == Any.of(47)));
    }
    writer.join();
    otherWriter.join();
    assert(context.lookupVariable("value") == Any.of(31));
    assert(context.lookupVariable("other").isNull());
}

@("variableAccess") unittest
{
    auto context = new StandardEvaluationContext;
    context.setVariable("answer", Any.of(42));
    auto parser = new SpelExpressionParser;

    auto variable = parser.parseExpression("#answer");
    assert(variable.getValue(context).typeName() == "int");
    assert(variable.getValue(context).get!int == 42);
    assert(variable.isWritable(context));

    auto quotient = parser.parseRaw("#answer / 2");
    assert(quotient.getValue(context).typeName() == "int");
    assert(quotient.getValue(context).get!int == 21);
    assert(!quotient.isWritable(context));
    auto read = () nothrow @nogc => quotient.evaluate(context);
    auto evaluated = read();
    assert(evaluated.ok() && evaluated.value == Any.of(21));

    context.setVariable("answer", Any.of(42L));
    assert(quotient.getValue(context).typeName() == "long");
    assert(quotient.getValue(context).get!long == 21L);
    context.setVariable("answer", Any.of(cast(short) 42));
    assert(quotient.getValue(context) == Any.of(21));
}

@("numeric references use explicit roots and late-bound context lookups") unittest
{
    static final class CustomContext : EvaluationContext
    {
        int calls;

        TypedValue getRootObject()
        {
            return TypedValue(Any.of(calls++));
        }

        void setVariable(string, Any)
        {
        }

        Any lookupVariable(string name)
        {
            if (name == "skipped")
                throw new IllegalStateException("skipped variable was read");
            calls++;
            return Any.of(name == "scale" ? 2L : 5L);
        }
    }

    auto standard = new StandardEvaluationContext(Any.of(1));
    standard.setVariable("scale", Any.of(2L));
    standard.setVariable("offset", Any.of(5L));
    auto custom = new CustomContext;

    auto expression = (new SpelExpressionParser).parseRaw("#root + (#this + #scale) * #offset");
    assert(expression.getValue(standard, Any.of(3)) == Any.of(28L));
    assert(expression.getValue(custom, Any.of(3)) == Any.of(28L));
    assert(custom.calls == 2);
    assert(expression.getValue(custom) == Any.of(22L));
    assert(custom.calls == 5);

    auto branch = (new SpelExpressionParser).parseRaw("false && #skipped");
    assert(branch.getValue(custom).get!bool == false);
    assert(custom.calls == 6);
}

@("a missing numeric variable fails during evaluation") unittest
{
    auto context = new StandardEvaluationContext;
    auto expression = (new SpelExpressionParser).parseExpression("#missing + 1");
    try
    {
        expression.getValue(context);
        assert(false, "The numeric operator requires a bound number");
    }
    catch (EvaluationException)
    {
    }
}
