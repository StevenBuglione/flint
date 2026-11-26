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
 * Ported from spring-framework v7.1.0: spring-expression/src/test/java/org/springframework/expression/spel/PropertyAccessTests.java
 * Modified by the Flint authors.
 */
module flint.expression.property_tests;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;
import flint.expression : TypedValue;
import flint.expression.spel : SpelEvaluationException, SpelMessage;
import flint.expression.spel.standard : SpelExpressionParser;
import flint.expression.spel.support : StandardEvaluationContext;
import flint.java.lang : IllegalStateException;

@safe:

private final class Place
{
    private string city = "Smiljan";

    string getCity() const
    {
        return city;
    }

    int getPopulation() const
    {
        return 400;
    }
}

private class Inventor
{
    private string name = "Nikola Tesla";
    private Place birthplace;
    private size_t placesRead;

    string getName() const
    {
        return name;
    }

    Place getPlaceOfBirth()
    {
        ++placesRead;
        return birthplace;
    }

    Place getCité()
    {
        return birthplace;
    }

    string getBroken()
    {
        throw new IllegalStateException("getter failed");
    }
}

private final class Engineer(Arguments...) : Inventor
{
    string getSpecialty() const
    {
        return "electrical";
    }
}

private DescriptorTable table()
{
    auto descriptors = new DescriptorTable;
    descriptors.add(descriptorOf!Inventor);
    descriptors.add(descriptorOf!Place);
    return descriptors;
}

private SpelEvaluationException failure(SpelExpressionParser parser, string source,
        StandardEvaluationContext context, SpelMessage code, int position)
{
    try
    {
        parser.parseExpression(source).getValue(context);
        assert(false, source);
    }
    catch (SpelEvaluationException error)
    {
        assert(error.getPosition() == position, source);
        assert(error.getMessageCode() == code, source);
        return error;
    }
}

@("simpleAccess01") unittest
{
    auto root = new Inventor;
    auto context = new StandardEvaluationContext(Any.of(root));
    context.setDescriptorTable(table());
    auto expression = (new SpelExpressionParser).parseExpression("name");
    assert(expression.getValue(context).get!string == "Nikola Tesla");
    root.name = "Tesla";
    assert(expression.getValue(context).get!string == "Tesla");
    assert(!expression.isWritable(context));
}

@("simpleAccess02") unittest
{
    auto root = new Inventor;
    root.birthplace = new Place;
    auto context = new StandardEvaluationContext(Any.of(root));
    context.setDescriptorTable(table());
    auto parser = new SpelExpressionParser;
    assert(parser.parseExpression("placeOfBirth.city").getValue(context).get!string == "Smiljan");
    assert(parser.parseExpression("#this . placeOfBirth").getValue(context).asObject() is root.birthplace);
}

@("property lookup uses the registered runtime subtype of a boxed base reference")
unittest
{
    Inventor root = new Engineer!int;
    auto descriptors = table();
    descriptors.add(descriptorOf!(Engineer!int));
    auto context = new StandardEvaluationContext(Any.of(root));
    context.setDescriptorTable(descriptors);
    auto parser = new SpelExpressionParser;
    assert(parser.parseExpression("specialty").getValue(context).get!string == "electrical");

    auto baseOnly = new StandardEvaluationContext(Any.of(root));
    baseOnly.setDescriptorTable(table());
    assert(parser.parseExpression("name").getValue(baseOnly).get!string == "Nikola Tesla");

    auto complexDescriptors = table();
    complexDescriptors.add(descriptorOf!(Engineer!(int, string)));
    Inventor complexRoot = new Engineer!(int, string);
    auto complex = new StandardEvaluationContext(Any.of(complexRoot));
    complex.setDescriptorTable(complexDescriptors);
    assert(parser.parseExpression("specialty").getValue(complex).get!string == "electrical");
}

@("nonExistentPropertiesAndMethods") unittest
{
    auto context = new StandardEvaluationContext(Any.of(new Inventor));
    auto parser = new SpelExpressionParser;
    const missing = SpelMessage.PROPERTY_OR_FIELD_NOT_READABLE;
    failure(parser, "madeup", context, missing, 0);
    context.setDescriptorTable(table());
    failure(parser, "madeup", context, missing, 0);
    auto nested = failure(parser, "name.foobar", context, missing, 5);
    const expected = "EL1008E: Property or field 'foobar' cannot be found on object of type 'string'"
        ~ " - maybe not public or not valid?";
    assert(nested.getSimpleMessage() == expected);
}

@("null-safe navigation of an absent root")
unittest
{
    auto parser = new SpelExpressionParser;
    auto path = parser.parseExpression("#root?.name");
    assert(path.getValue().isNull());
    assert(parser.parseExpression("#root?.placeOfBirth?.city").getValue().isNull());
    failure(parser, "#root?.placeOfBirth.city", new StandardEvaluationContext,
            SpelMessage.PROPERTY_OR_FIELD_NOT_READABLE_ON_NULL, 20);
}

@("null navigation checks each hop and keeps UTF-16 diagnostic positions")
unittest
{
    auto root = new Inventor;
    auto context = new StandardEvaluationContext(Any.of(root));
    context.setDescriptorTable(table());
    auto parser = new SpelExpressionParser;
    auto path = parser.parseExpression("#root.placeOfBirth?.city");
    assert(path.getValue(context).isNull());
    assert(root.placesRead == 1);
    const nullRead = SpelMessage.PROPERTY_OR_FIELD_NOT_READABLE_ON_NULL;
    failure(parser, "cité.city", context, nullRead, 5);
    failure(parser, "placeOfBirth?.city.madeup", context, nullRead, 19);
    failure(parser, "#root.name", new StandardEvaluationContext, nullRead, 6);
    root.birthplace = new Place;
    assert(path.getValue(context).get!string == "Smiljan");
    assert(root.placesRead == 3);
}

@("descriptor-backed contexts preserve explicit roots and virtual default roots")
unittest
{
    static final class DerivedContext : StandardEvaluationContext
    {
        private Any root;

        this(Any root)
        {
            this.root = root;
        }

        override TypedValue getRootObject()
        {
            return TypedValue(root);
        }
    }

    auto context = new DerivedContext(Any.of(new Inventor));
    context.setDescriptorTable(table());
    auto expression = (new SpelExpressionParser).parseExpression("#root?.name");
    assert(expression.getValue(context).get!string == "Nikola Tesla");
    assert(expression.getValue(context, Any.init).isNull());
}

@("property getter failures retain their cause")
unittest
{
    auto context = new StandardEvaluationContext(Any.of(new Inventor));
    context.setDescriptorTable(table());
    auto error = failure(new SpelExpressionParser, "#root.broken", context,
            SpelMessage.EXCEPTION_DURING_PROPERTY_READ, 6);
    assert(cast(IllegalStateException) error.getCause() !is null);
}

@("property paths are operands in arithmetic and boolean expressions")
unittest
{
    auto inventor = new Inventor;
    inventor.birthplace = new Place;
    auto context = new StandardEvaluationContext(Any.of(inventor));
    context.setDescriptorTable(table());
    context.setVariable("other", Any.of(inventor));
    auto parser = new SpelExpressionParser;

    assert(parser.parseExpression("placeOfBirth.population + 2").getValue(context).get!int == 402);
    assert(parser.parseExpression("#other.placeOfBirth.population / 2").getValue(context).get!int == 200);
    assert(parser.parseExpression("name == 'Nikola Tesla' && #this.placeOfBirth.population > 300")
            .getValue(context).get!bool);
    assert(parser.parseExpression("#other.placeOfBirth").getValue(context).asObject() is inventor.birthplace);
}

@("conditionals read properties only in evaluated branches")
unittest
{
    auto context = new StandardEvaluationContext(Any.of(new Inventor));
    context.setDescriptorTable(table());
    auto parser = new SpelExpressionParser;

    assert(parser.parseExpression("false && broken == 'called'").getValue(context).get!bool == false);
    assert(parser.parseExpression("true ? 20 : #root.broken").getValue(context).get!int == 20);
    assert(parser.parseExpression("name ?: broken").getValue(context).get!string == "Nikola Tesla");
    assert(parser.parseExpression("placeOfBirth?.population ?: 21").getValue(context).get!int == 21);
    failure(parser, "false ? 'unused' : broken", context, SpelMessage.EXCEPTION_DURING_PROPERTY_READ, 19);
}
