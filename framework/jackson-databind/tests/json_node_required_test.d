/*
 * Ported from Jackson (jackson-databind) 3.1.8, tag jackson-databind-3.1.8:
 * src/test/java/tools/jackson/databind/node/RequiredAccessorTest.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated direct required-access assertions to D unittests.
 */
module json_node_required_test;

import flint.jackson.databind : JsonMapper;
import flint.jackson.databind.node : JsonNode, JsonNodeException;

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
