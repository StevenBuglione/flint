/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/test/web/servlet/result/JsonPathResultMatchersTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors. The fixture uses standard JSON quoting.
+/
module json_path_result_matchers_tests;

import flint.java.lang : AssertionError;
import flint.mock.web : MockHttpServletResponse;
import flint.test.web.servlet : DefaultMvcResult, MvcResult, ResultMatcher;
import flint.test.web.servlet.result : MockMvcResultMatchers;

@safe:

private alias jsonPath = MockMvcResultMatchers.jsonPath;
private enum content = `{"str":"foo","utf8Str":"Příliš","num":5,"bool":true,"arr":[42],`
    ~ `"colorMap":{"red":"rojo"},"emptyString":"","emptyArray":[],"emptyMap":{}}`;

private MvcResult result(string body = content)
{
    auto response = new MockHttpServletResponse;
    response.addHeader("Content-Type", "application/json");
    response.getOutputStream().write(cast(const(ubyte)[])
            body);
    return new DefaultMvcResult(null, response);
}

private void fails(ResultMatcher matcher, string body = content, string message = null)
{
    try
    {
        matcher.match(result(body));
        assert(false);
    }
    catch (AssertionError failure)
    {
        if (message !is null)
            assert(failure.getMessage() == message, failure.getMessage());
    }
}

@("valueWithValueMismatch")
unittest
{
    fails(jsonPath("$.str").value("bogus"), content, `JSON path "$.str" expected:<bogus> but was:<foo>`);
}

@("valueWithTypeMismatch")
unittest
{
    enum message = `At JSON path "$.str", value <foo> of type <java.lang.String> cannot be converted to type <byte[]>`;
    fails(jsonPath("$.str").value(cast(byte[]) "bogus".dup), content, message);
}

@("valueWithDirectMatch")
unittest
{
    jsonPath("$.str").value("foo").match(result());
}

@("utf8ValueWithDirectMatch")
unittest
{
    jsonPath("$.utf8Str").value("Příliš").match(result());
}

@("valueWithNumberConversion")
unittest
{
    jsonPath("$.num").value(5.0f).match(result());
}

@("valueWithJsonPrefixNotConfigured")
unittest
{
    fails(jsonPath("$.str").value("foo"), "prefix" ~ content);
}

@("valueWithJsonWrongPrefix")
unittest
{
    fails(jsonPath("$.str").prefix("wrong").value("foo"), "prefix" ~ content);
}

@("valueWithJsonPrefix")
unittest
{
    jsonPath("$.str").prefix("prefix").value("foo").match(result("prefix" ~ content));
}

@("prefixWithPayloadNotLongEnough")
unittest
{
    fails(jsonPath("$.str").prefix("prefix").value("foo"), "test", `JSON prefix "prefix" not found`);
}

@("MockMvc distinguishes a JSON null from a missing path")
unittest
{
    auto actual = result(`{"value":null}`);
    jsonPath("$.value").hasJsonPath().match(actual);
    jsonPath("$.value").doesNotExist().match(actual);
    jsonPath("$.absent").doesNotHaveJsonPath().match(actual);
    fails(jsonPath("$.value").exists(), `{"value":null}`);
    fails(jsonPath("$.value").doesNotHaveJsonPath(), `{"value":null}`);
}

@("MockMvc formats JSON paths with numbered Java arguments")
unittest
{
    jsonPath("$.%2$s[%1$d]", 0, "arr").value(42).match(result());
}

@("exists")
unittest
{
    jsonPath("$.str").exists().match(result());
}

@("existsForAnEmptyArray")
unittest
{
    jsonPath("$.emptyArray").exists().match(result());
}

@("existsForAnEmptyMap")
unittest
{
    jsonPath("$.emptyMap").exists().match(result());
}

@("existsNoMatch")
unittest
{
    fails(jsonPath("$.bogus").exists());
}

@("doesNotExist")
unittest
{
    jsonPath("$.bogus").doesNotExist().match(result());
}

@("doesNotExistNoMatch")
unittest
{
    fails(jsonPath("$.str").doesNotExist());
}

@("doesNotExistForAnEmptyArray")
unittest
{
    fails(jsonPath("$.emptyArray").doesNotExist());
}

@("doesNotExistForAnEmptyMap")
unittest
{
    fails(jsonPath("$.emptyMap").doesNotExist());
}

@("isEmptyForAnEmptyString")
unittest
{
    jsonPath("$.emptyString").isEmpty().match(result());
}

@("isEmptyForAnEmptyArray")
unittest
{
    jsonPath("$.emptyArray").isEmpty().match(result());
}

@("isEmptyForAnEmptyMap")
unittest
{
    jsonPath("$.emptyMap").isEmpty().match(result());
}

@("isNotEmptyForString")
unittest
{
    jsonPath("$.str").isNotEmpty().match(result());
}

@("isNotEmptyForNumber")
unittest
{
    jsonPath("$.num").isNotEmpty().match(result());
}

@("isNotEmptyForBoolean")
unittest
{
    jsonPath("$.bool").isNotEmpty().match(result());
}

@("isNotEmptyForArray")
unittest
{
    jsonPath("$.arr").isNotEmpty().match(result());
}

@("isNotEmptyForMap")
unittest
{
    jsonPath("$.colorMap").isNotEmpty().match(result());
}

@("isNotEmptyForAnEmptyString")
unittest
{
    fails(jsonPath("$.emptyString").isNotEmpty());
}

@("isNotEmptyForAnEmptyArray")
unittest
{
    fails(jsonPath("$.emptyArray").isNotEmpty());
}

@("isNotEmptyForAnEmptyMap")
unittest
{
    fails(jsonPath("$.emptyMap").isNotEmpty());
}

@("isArray")
unittest
{
    jsonPath("$.arr").isArray().match(result());
}

@("isArrayForAnEmptyArray")
unittest
{
    jsonPath("$.emptyArray").isArray().match(result());
}

@("isArrayNoMatch")
unittest
{
    fails(jsonPath("$.bar").isArray());
}

@("isMap")
unittest
{
    jsonPath("$.colorMap").isMap().match(result());
}

@("isMapForAnEmptyMap")
unittest
{
    jsonPath("$.emptyMap").isMap().match(result());
}

@("isMapNoMatch")
unittest
{
    fails(jsonPath("$.str").isMap());
}

@("isBoolean")
unittest
{
    jsonPath("$.bool").isBoolean().match(result());
}

@("isBooleanNoMatch")
unittest
{
    fails(jsonPath("$.str").isBoolean());
}

@("isNumber")
unittest
{
    jsonPath("$.num").isNumber().match(result());
}

@("isNumberNoMatch")
unittest
{
    fails(jsonPath("$.str").isNumber());
}

@("isString")
unittest
{
    jsonPath("$.str").isString().match(result());
}

@("isStringNoMatch")
unittest
{
    fails(jsonPath("$.arr").isString());
}
