/*
 * Ported from Jackson (jackson-databind) 3.1.8, tag jackson-databind-3.1.8:
 * src/test/java/tools/jackson/databind/node/JsonNodeFindMethodsTest.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated JUnit assertions to D unittests.
 */
module json_node_find_methods_test;

import flint.jackson.databind : JsonMapper;
import flint.jackson.databind.node : JsonNodeFactory;

@safe:

private enum sample = `{"a":{"value":3},"array":[{"b":3},{"value":42},{"other":true}]}`;

@("testMatchingSingle")
unittest
{
    auto root = JsonMapper.builder().build().readTree(sample);

    auto value = root.findValue("b");
    assert(value.intValue() == 3);
    assert(root.findPath("b") is value);
    auto parent = root.findParent("b");
    assert(parent.isObject());
    assert(parent.size() == 1);
    assert(parent.path("b") is value);
}

@("absent tree searches return null or a missing node")
unittest
{
    auto root = JsonMapper.builder().build().readTree(sample);
    assert(root.findValue("boogaboo") is null);
    assert(root.findParent("boogaboo") is null);
    assert(root.findPath("boogaboo").isMissingNode());

    auto leaf = JsonNodeFactory.instance.numberNode(1);
    assert(leaf.findParent("b") is null);
    assert(leaf.findPath("b").isMissingNode());
}

@("first matches prefer a property on the current object including explicit null")
unittest
{
    auto root = JsonMapper.builder().build()
        .readTree(`{"first":{"target":1},"target":null,"last":[[{"target":2}]]}`).asObject();

    assert(root.findValue("target") is root.get("target"));
    assert(root.findPath("target").isNull());
    assert(root.findParent("target") is root);

    auto nested = root.get("last").asArray();
    assert(nested.findPath("target").intValue() == 2);
    assert(nested.findParent("target") is nested.get(0).get(0));
}
