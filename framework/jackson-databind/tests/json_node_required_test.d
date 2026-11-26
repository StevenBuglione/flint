/*
 * Ported from Jackson (jackson-databind) 3.1.8, tag jackson-databind-3.1.8:
 * src/test/java/tools/jackson/databind/node/RequiredAccessorTest.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated required-access assertions to D unittests.
 */
module json_node_required_test;

import flint.jackson.core : JsonPointer;
import flint.jackson.databind : JsonMapper;
import flint.jackson.databind.node : ArrayNode, JsonNode, JsonNodeException, MissingNode, NullNode, ObjectNode;
import flint.java.lang : ClassCastException, NullPointerException;
import std.exception : assertThrown;

@safe:

private void assertRequiredViolation(scope JsonNode delegate() @safe access, string message)
{
    try
        access();
    catch (JsonNodeException error)
    {
        assert(error.msg == message, error.msg);
        return;
    }
    assert(false, "required access unexpectedly succeeded");
}

@("testSimpleRequireFail")
unittest
{
    auto mapper = JsonMapper.builder().build();
    auto objectNode = mapper.readTree(`{"data":{"primary":15},"array":[true,null]}`);
    auto arrayNode = mapper.readTree(`[true, {"data":{"primary":15}}, 0.25, "last"]`);

    assertRequiredViolation(() => objectNode.required("bogus"), "No value for property 'bogus' of `ObjectNode`");
    assertRequiredViolation(() => arrayNode.required("bogus"),
            "Node of type `flint.jackson.databind.node.ArrayNode` has no fields");
    assertRequiredViolation(() => objectNode.required(-1),
            "Node of type `flint.jackson.databind.node.ObjectNode` has no indexed values");
    assertRequiredViolation(() => arrayNode.required(-1), "No value at index #-1 [0, 4) of `ArrayNode`");
}

@("required child access returns the same node including explicit null")
unittest
{
    auto mapper = JsonMapper.builder().build();
    auto root = mapper.readTree(`{"data":null,"array":[0,null]}`);
    assert(root.required("data") is root.get("data"));
    assert(root.required("data").isNull());
    auto arrayNode = root.required("array");
    assert(arrayNode.required(0) is arrayNode.get(0));
    assert(arrayNode.required(1).isNull());
    assertRequiredViolation(() => arrayNode.required(2), "No value at index #2 [0, 2) of `ArrayNode`");
}

private JsonNode testObject()
{
    return JsonMapper.builder().build().readTree(`{
        "data":{"primary":15,"vector":["yes",false],"nullable":null},
        "array":[true,{"messsage":"hello","value":42,"misc":[1,2]},null,0.25]
    }`);
}

private JsonNode testArray()
{
    return JsonMapper.builder().build().readTree(`[true,{"data":{"primary":15,"vector":["yes",false]}},0.25,"last"]`);
}

private void checkRequiredAtFailure(JsonNode node, string expression, string unmatched)
{
    assertRequiredViolation(() => node.requiredAt(expression),
            "No node at '" ~ expression ~ "' (unmatched part: '" ~ unmatched ~ "')");
}

@("testIMPORTANT")
unittest
{
    checkRequiredAtFailure(testObject(), "/data/weird/and/more", "/weird/and/more");
}

@("testRequiredAtObjectOk")
unittest
{
    auto root = testObject();
    assert(root.requiredAt("/array") !is null);
    assert(root.requiredAt("/array/0").isBoolean());
    assert(root.requiredAt("/array/1/misc/1").intValue() == 2);
}

@("testRequiredAtArrayOk")
unittest
{
    auto root = testArray();
    assert(root.requiredAt("/0").isBoolean());
    assert(root.requiredAt("/1").isObject());
    assert(root.requiredAt("/1/data/primary") !is null);
    assert(root.requiredAt("/1/data/vector/1") !is null);
}

@("testRequiredAtFailOnObjectBasic")
unittest
{
    auto root = testObject();
    checkRequiredAtFailure(root, "/0", "/0");
    checkRequiredAtFailure(root, "/bogus", "/bogus");
    checkRequiredAtFailure(root, "/data/weird/and/more", "/weird/and/more");
    checkRequiredAtFailure(root, "/data/vector/other/3", "/other/3");
    checkRequiredAtFailure(root, "/data/primary/more", "/more");
}

@("testRequiredAtFailOnArray")
unittest
{
    auto root = testArray();
    checkRequiredAtFailure(root, "/1/data/vector/25", "/25");
    checkRequiredAtFailure(root, "/0/data/x", "/data/x");
}

@("testSimpleRequireAtFailure")
unittest
{
    const expression = "/some-random-path";
    const message = "No node at '/some-random-path' (unmatched part: '/some-random-path')";
    auto pointer = JsonPointer.compile(expression);
    auto obj = testObject();
    auto array = testArray();
    assertRequiredViolation(() => obj.requiredAt(expression), message);
    assertRequiredViolation(() => array.requiredAt(expression), message);
    assertRequiredViolation(() => obj.requiredAt(pointer), message);
    assertRequiredViolation(() => array.requiredAt(pointer), message);
}

@("testRequiredAtFailOnObjectScalar3005")
unittest
{
    auto root = JsonMapper.builder().build().readTree(`{"simple":5}`);
    checkRequiredAtFailure(root, "/simple/property", "/property");
}

@("tree pointers preserve escaped names, explicit null and missing identity")
unittest
{
    auto root = JsonMapper.builder().build().readTree(`{"a/b":{"~":[null]},"00":5}`);
    const nullValue = root.get("a/b").get("~").get(0);
    auto pointer = JsonPointer.compile("/a~1b/~0/0");
    assert(root.at(pointer) is nullValue);
    assert(root.requiredAt(pointer) is nullValue);
    assert(root.at("/00").intValue() == 5);
    assert(root.at("/a~1b/~0/00").isMissingNode());
    assert(root.at("") is root);
    assert(root.requiredAt(JsonPointer.empty()) is root);

    auto missing = root.path("absent");
    assert(missing.at("/anything") is missing);
    assert(missing.requiredAt("/anything") is missing);
    assertThrown!NullPointerException(root.at(cast(JsonPointer) null));
    assertThrown!NullPointerException(root.requiredAt(cast(JsonPointer) null));
}

@("testSimpleRequireOk")
unittest
{
    auto root = testObject();
    auto array = testArray();

    assert(root.require() is root);
    assert(root.requireNonNull() is root);
    assert(root.requiredAt("") is root);
    assert(root.requiredAt(JsonPointer.compile("")) is root);
    assert(root.required("data") is root.get("data"));
    assert(array.required(0) is array.get(0));
    assert(array.required(3) is array.get(3));

    auto nullable = root.path("data").path("nullable");
    assert(nullable.require() is nullable);
    assertRequiredViolation(() => nullable.requireNonNull(), "requireNonNull() called on `NullNode`");
}

@("explicit result types are checked after the required node check")
unittest
{
    auto root = testObject();
    auto array = testArray();
    assert(root.require!ObjectNode() is root);
    assert(array.requireNonNull!ArrayNode() is array);
    assertThrown!ClassCastException(root.require!ArrayNode());
    assertThrown!ClassCastException(array.requireNonNull!ObjectNode());

    auto missing = MissingNode.getInstance();
    assertRequiredViolation(() => missing.require!ObjectNode(), "require() called on `MissingNode`");
    assertRequiredViolation(() => missing.requireNonNull(), "requireNonNull() called on `MissingNode`");

    auto nullable = cast(NullNode) root.path("data").path("nullable");
    assert(nullable.require!NullNode() is nullable);
    assertRequiredViolation(() => nullable.requireNonNull!NullNode(), "requireNonNull() called on `NullNode`");
}
