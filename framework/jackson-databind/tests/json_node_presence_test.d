/*
 * Ported from Jackson (jackson-databind) 3.1.8, tag jackson-databind-3.1.8:
 * src/test/java/tools/jackson/databind/node/{ArrayNodeTest,ObjectNodeTest}.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated the presence assertions to D unittests.
 */
module json_node_presence_test;

import flint.jackson.databind.node : JsonNode, JsonNodeFactory;

@safe:

@("ArrayNode presence distinguishes an absent index from explicit null")
unittest
{
    auto array = JsonNodeFactory.instance.arrayNode();
    array.add("x");
    assert(!array.has("field") && !array.hasNonNull("field"));
    assert(array.has(0) && array.hasNonNull(0));
    assert(!array.has(1) && !array.hasNonNull(1));

    array.add(cast(JsonNode) null);
    assert(array.has(1) && !array.hasNonNull(1));
    array.set(1, array.get(0));
    assert(array.hasNonNull(1));
}

@("ObjectNode presence distinguishes an absent property from explicit null")
unittest
{
    auto factory = JsonNodeFactory.instance;
    auto node = factory.objectNode();
    node.set("a", factory.textNode("x"));
    assert(!node.has(0) && !node.hasNonNull(0));
    assert(node.has("a") && node.hasNonNull("a"));
    assert(!node.has("b") && !node.hasNonNull("b"));

    node.set("null", null);
    assert(node.has("null") && !node.hasNonNull("null"));
    node.put("null", "replacement");
    assert(node.hasNonNull("null"));
}
