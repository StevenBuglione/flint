/++
`org.springframework.test.util`: assertion helpers and JSON path evaluation for test matchers.

Ported from spring-projects/spring-framework v7.1.0, spring-test/src/main/java/org/springframework/test/util/
(AssertionErrors.java, JsonPathExpectationsHelper.java).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: failures throw `flint.java.lang.AssertionError`, a D `Exception` (rulebook R8).
The helper evaluates paths against the Jackson tree (D-TEST-2).
+/
module flint.test.util;

import flint.engine.aot.text : decimal, doubleText, tryParseLong, tryParseULong;
import flint.jackson.databind : JsonMapper;
import flint.jackson.databind.node : JsonNode, JsonNodeFactory, JsonNodeType;
import flint.java.lang : AssertionError, IllegalArgumentException, String, valueOf;
import flint.util : Assert;

@safe:

/// `AssertionErrors`.
struct AssertionErrors
{
    /// Fails with `message`.
    static void fail(string message)
    {
        throw new AssertionError(message);
    }

    /// Fails with `message` and Spring's `expected:<...> but was:<...>` suffix.
    static void fail(string message, string expected, string actual)
    {
        throw new AssertionError(message ~ " expected:<" ~ expected ~ "> but was:<" ~ actual ~ ">");
    }

    /// Fails unless `condition`.
    static void assertTrue(string message, bool condition)
    {
        if (!condition)
            fail(message);
    }

    /// Fails if `condition`.
    static void assertFalse(string message, bool condition)
    {
        if (condition)
            fail(message);
    }

    /// Fails if `object` is not null.
    static void assertNull(string message, bool isNull)
    {
        if (!isNull)
            fail(message);
    }

    /// Fails if `object` is null.
    static void assertNotNull(string message, bool isNull)
    {
        if (isNull)
            fail(message);
    }

    /// Fails unless `expected == actual`.
    static void assertEquals(T, U)(string message, T expected, U actual)
    {
        if (!(expected == actual))
            fail(message, text(expected), text(actual));
    }

    /// Fails if `expected == actual`.
    static void assertNotEquals(T, U)(string message, T expected, U actual)
    {
        if (expected == actual)
            fail(message ~ " was not expected to be:<" ~ text(actual) ~ ">");
    }

    private static string text(T)(T value)
    {
        static if (is(T == typeof(null)))
            return "null";
        else static if (is(T : const(char)[]))
            return value is null ? "null" : value.idup;
        else static if (is(T == struct) && __traits(hasMember, T, "toString"))
            return value.toString();
        else static if (is(T == class))
            return value is null ? "null" : typeid(value).name;
        else static if (is(T == float) || is(T == double))
            return doubleText(value);
        else static if (is(T == bool) || __traits(isIntegral, T))
            return valueOf(value);
        else static if (is(T : const(ubyte)[]))
            return byteArrayText(value, false);
        else static if (is(T : const(byte)[]))
            return byteArrayText(cast(const(ubyte)[]) value, true);
        else
        {
            import std.conv : to;

            return value.to!string;
        }
    }

    private static string byteArrayText(scope const(ubyte)[] bytes, bool signedBytes) pure nothrow
    {
        string result = "[";
        foreach (index, octet; bytes)
        {
            if (index != 0)
                result ~= ", ";
            result ~= decimal(signedBytes ? cast(byte) octet : cast(int) octet);
        }
        return result ~ "]";
    }
}

/// Evaluates a compiled JSON path against the Jackson tree and asserts on its result (D-TEST-2).
struct JsonPathExpectationsHelper
{
    private enum Selection : ubyte
    {
        member,
        element,
        wildcard,
        descendant,
    }

    private struct Step
    {
        Selection selection;
        string name;
        long index;
    }

    private string expression;
    private Step[] steps;
    private bool pathDefinite = true;
    private JsonMapper mapper;

    /// Compiles an expression. Supported steps are names, indices, wildcards and named recursive descent.
    this(string expression)
    {
        Assert.hasText(expression, "expression must not be null or empty");
        this.expression = expression;
        compile();
        mapper = new JsonMapper;
    }

    /// Formats the expression using Java's format specifiers (R7).
    this(Args...)(string expression, Args args) if (Args.length != 0)
    {
        this(String.format(expression, args));
    }

    /// The expression.
    string getExpression() const pure nothrow @nogc
    {
        return expression;
    }

    /// Asserts equality after converting the selected value to the expected type.
    void assertValue(T)(string content, T expectedValue)
    {
        auto actual = evaluateJsonPath(content);
        static if (!is(T == E[], E) || is(T : const(char)[]))
        {
            if (!pathDefinite)
            {
                if (actual.isEmpty())
                    AssertionErrors.fail("No matching value at JSON path \"" ~ expression ~ "\"");
                if (actual.size() != 1)
                    AssertionErrors.fail("Got a list of values " ~ actual.toString()
                            ~ " instead of the expected single value " ~ AssertionErrors.text(expectedValue));
                actual = actual.get(0);
            }
        }
        T converted;
        if (!convert(actual, converted))
        {
            const value = actual.isString() ? actual.asString() : actual.toString();
            AssertionErrors.fail("At JSON path \"" ~ expression ~ "\", value <" ~ value ~ "> of type <" ~ jsonTypeName(
                    actual) ~ "> cannot be converted to type <" ~ T.stringof ~ ">");
        }
        AssertionErrors.assertEquals("JSON path \"" ~ expression ~ "\"", expectedValue, converted);
    }

    /// Asserts that a non-null value or a non-empty indefinite selection exists.
    void exists(string content)
    {
        auto value = evaluateJsonPath(content);
        if (value.isNull() || (!pathDefinite && value.isEmpty()))
            AssertionErrors.fail("No value at JSON path \"" ~ expression ~ "\"");
    }

    /// Asserts that no non-null value exists.
    void doesNotExist(string content)
    {
        assertAbsent(content, true);
    }

    /// Asserts that a selection exists, including a JSON null at a definite path.
    void hasJsonPath(string content)
    {
        auto value = evaluateJsonPath(content);
        if (!pathDefinite && value.isEmpty())
            AssertionErrors.fail("No values for JSON path \"" ~ expression ~ "\"");
    }

    /// Asserts that the path selects no value, including a JSON null.
    void doesNotHaveJsonPath(string content)
    {
        assertAbsent(content, false);
    }

    private void assertAbsent(string content, bool allowNull)
    {
        JsonNode value;
        try
            value = evaluateJsonPath(content);
        catch (AssertionError)
            return;

        if (pathDefinite)
        {
            if (!allowNull || !value.isNull())
                failExpectation("no value", value);
        }
        else if (!value.isEmpty())
            failExpectation(allowNull ? "no value" : "no values", value);
    }

    /// Asserts that the selection is an array.
    void assertValueIsArray(string content)
    {
        assertType(content, JsonNodeType.ARRAY, "an array");
    }

    /// Asserts that the selection is an object.
    void assertValueIsMap(string content)
    {
        assertType(content, JsonNodeType.OBJECT, "a map");
    }

    /// Asserts that the selection is a string.
    void assertValueIsString(string content)
    {
        assertType(content, JsonNodeType.STRING, "a string");
    }

    /// Asserts that the selection is a boolean.
    void assertValueIsBoolean(string content)
    {
        assertType(content, JsonNodeType.BOOLEAN, "a boolean");
    }

    /// Asserts that the selection is a number.
    void assertValueIsNumber(string content)
    {
        assertType(content, JsonNodeType.NUMBER, "a number");
    }

    /// Asserts that the selection is empty.
    void assertValueIsEmpty(string content)
    {
        auto value = evaluateJsonPath(content);
        if (!isEmpty(value))
            failExpectation("an empty value", value);
    }

    /// Asserts that the selection has content.
    void assertValueIsNotEmpty(string content)
    {
        auto value = evaluateJsonPath(content);
        if (isEmpty(value))
            failExpectation("a non-empty value", value);
    }

    private void assertType(string content, JsonNodeType type, string description)
    {
        auto value = evaluateJsonPath(content);
        if (value.isNull() || (!pathDefinite && value.isEmpty()))
            AssertionErrors.fail("No value at JSON path \"" ~ expression ~ "\"");
        if (value.getNodeType() != type)
            failExpectation(description, value);
    }

    private void failExpectation(string description, JsonNode value)
    {
        const text = value.isString() ? "'" ~ value.asString() ~ "'" : value.toString();
        AssertionErrors.fail("Expected " ~ description ~ " at JSON path \"" ~ expression ~ "\" but found: " ~ text);
    }

    private static bool isEmpty(JsonNode value)
    {
        if (value.isString())
            return value.asString().length == 0;
        return value.isNull() || (value.isContainer() && value.isEmpty());
    }

    /// Returns the selected node, or an array of matches for an indefinite path.
    JsonNode evaluateJsonPath(string content)
    {
        bool definite;
        auto values = evaluate(content, definite);
        if (!definite)
        {
            auto array = JsonNodeFactory.instance().arrayNode();
            foreach (value; values)
                array.add(value);
            return array;
        }
        if (values.length == 0)
            AssertionErrors.fail("No value at JSON path \"" ~ expression ~ "\"");
        return values[0];
    }

    /// Returns all selected Jackson nodes and reports whether the expression is definite (D-TEST-2).
    JsonNode[] evaluate(string content, out bool definite)
    {
        if (mapper is null)
            throw new IllegalArgumentException("expression must not be null or empty");
        JsonNode root;
        try
            root = mapper.readTree(content);
        catch (Exception malformed)
            throw new AssertionError("No value at JSON path \"" ~ expression ~ "\"", malformed);
        if (root.isMissingNode())
            AssertionErrors.fail("No value at JSON path \"" ~ expression ~ "\"");

        definite = pathDefinite;
        JsonNode[] current = [root];
        foreach (ref step; steps)
        {
            JsonNode[] next;
            foreach (value; current)
                select(value, step, next);
            current = next;
        }
        return current;
    }

    private void compile()
    {
        if (expression[0] != '$')
            invalidPath();
        size_t cursor = 1;
        while (cursor < expression.length)
        {
            Step step;
            switch (expression[cursor++])
            {
            case '.':
                step = compileDot(cursor);
                break;
            case '[':
                step = compileBracket(cursor);
                break;
            default:
                invalidPath();
            }
            if (step.selection == Selection.wildcard || step.selection == Selection.descendant)
                pathDefinite = false;
            steps ~= step;
        }
    }

    private Step compileDot(ref size_t cursor)
    {
        auto selection = Selection.member;
        if (cursor < expression.length && expression[cursor] == '*')
        {
            ++cursor;
            return Step(Selection.wildcard);
        }
        if (cursor < expression.length && expression[cursor] == '.')
        {
            ++cursor;
            selection = Selection.descendant;
        }
        const start = cursor;
        while (cursor < expression.length && expression[cursor] != '.' && expression[cursor] != '[')
            ++cursor;
        if (start == cursor)
            invalidPath();
        return Step(selection, expression[start .. cursor]);
    }

    private Step compileBracket(ref size_t cursor)
    {
        const start = cursor;
        while (cursor < expression.length && expression[cursor] != ']')
            ++cursor;
        if (cursor == expression.length || cursor == start)
            invalidPath();
        const token = expression[start .. cursor++];
        if (token == "*")
            return Step(Selection.wildcard);
        if (token.length >= 2 && (token[0] == '\'' || token[0] == '"') && token[$ - 1] == token[0])
            return Step(Selection.member, token[1 .. $ - 1]);
        const index = tryParseLong(token);
        if (!index.ok)
            throw new IllegalArgumentException("Unsupported JSON path element [" ~ token ~ "] in " ~ expression);
        return Step(Selection.element, null, index.value);
    }

    private void invalidPath()
    {
        throw new IllegalArgumentException("Invalid JSON path: " ~ expression);
    }

    private static void select(JsonNode value, ref const Step step, ref JsonNode[] selected)
    {
        final switch (step.selection)
        {
        case Selection.member:
            if (auto member = value.get(step.name))
                selected ~= member;
            break;
        case Selection.element:
            const index = step.index < 0 ? value.size() + step.index : step.index;
            if (value.isArray() && index >= 0 && index < value.size())
                selected ~= value.get(cast(int) index);
            break;
        case Selection.wildcard:
            selected ~= value.values();
            break;
        case Selection.descendant:
            deepScan(value, step.name, selected);
            break;
        }
    }

    private static void deepScan(JsonNode value, string name, ref JsonNode[] selected)
    {
        if (auto member = value.get(name))
            selected ~= member;
        foreach (child; value.values())
            deepScan(child, name, selected);
    }

    private static string jsonTypeName(JsonNode value)
    {
        switch (value.getNodeType())
        {
        case JsonNodeType.STRING:
            return "java.lang.String";
        case JsonNodeType.NUMBER:
            return value.isIntegralNumber() ? "java.lang.Integer" : "java.lang.Double";
        case JsonNodeType.BOOLEAN:
            return "java.lang.Boolean";
        case JsonNodeType.ARRAY:
            return "net.minidev.json.JSONArray";
        case JsonNodeType.OBJECT:
            return "java.util.LinkedHashMap";
        default:
            return "null";
        }
    }

    private static bool convert(T)(JsonNode value, out T result)
    {
        static if (is(T == typeof(null)))
            return value.isNull();
        else static if (is(T : const(char)[]))
        {
            if (value.isNull())
                return true;
            if (!value.isString())
                return false;
            result = value.asString();
            return true;
        }
        else static if (is(T == bool))
        {
            if (!value.isBoolean())
                return false;
            result = value.booleanValue();
            return true;
        }
        else static if (__traits(isIntegral, T))
        {
            if (!value.isIntegralNumber())
                return false;
            if (value.isBigInteger() && T.min == 0)
            {
                const number = tryParseULong(value.asString());
                if (!number.ok || number.value > T.max)
                    return false;
                result = cast(T) number.value;
                return true;
            }
            if (value.isBigInteger())
                return false;
            const number = value.longValue();
            if (number < T.min || number > T.max)
                return false;
            result = cast(T) number;
            return true;
        }
        else static if (__traits(isFloating, T))
        {
            if (!value.isNumber())
                return false;
            result = cast(T) value.doubleValue();
            return true;
        }
        else static if (is(T == E[], E))
        {
            if (!value.isArray())
                return false;
            result = new E[value.size()];
            foreach (index; 0 .. value.size())
                if (!convert(value.get(index), result[index]))
                    return false;
            return true;
        }
        else
            return false;
    }
}
