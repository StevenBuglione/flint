// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionalOnBooleanPropertyTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: invalid attributes are diagnosed during AOT generation.
module flint_tool.engine.aot_boolean_property_test;

import flint_tool.engine.aot.conditions : ConditionOutcome, evaluate;
import flint_tool.engine.aot.merge : merge;
import flint_tool.engine.aot.model : Annotation, Value;
import flint_tool.engine.aot.names : onBooleanProperty;

@safe:

@("nameOrValueMustBeSpecified") unittest
{
    const outcome = evaluateProperties([Annotation(type: onBooleanProperty)]);
    assert(outcome.errors == [
        "The name or value attribute of @ConditionalOnBooleanProperty must be specified"
    ]);
    assert(outcome.codes == ["FLINT-E1118"]);
}

@("nameAndValueMustNotBeSpecified") unittest
{
    auto property = Annotation(type: onBooleanProperty);
    property.set("value", names("x"));
    property.set("name", names("y"));
    const outcome = evaluateProperties([property]);
    assert(outcome.errors == [
        "The name and value attributes of @ConditionalOnBooleanProperty are exclusive"
    ]);
    assert(outcome.codes == ["FLINT-E1118"]);
}

@("Boolean property conditions retain their prefix, expected value and missing-property policy") unittest
{
    auto property = Annotation(type: onBooleanProperty);
    property.set("name", names("enabled"));
    property.set("prefix", Value(kind: Value.Kind.text, text: "jobs"));
    property.set("havingValue", Value(kind: Value.Kind.boolean, boolean: false));
    property.set("matchIfMissing", Value(kind: Value.Kind.boolean, boolean: true));

    const outcome = evaluateProperties([property]);
    assert(outcome.errors.length == 0);
    assert(outcome.terms == [`c.property("jobs.enabled", "false", true)`]);
}

private Value names(string name)
{
    return Value(kind: Value.Kind.array, items: [Value(kind: Value.Kind.text, text: name)]);
}

private ConditionOutcome evaluateProperties(Annotation[] annotations)
{
    const merged = merge(annotations, null);
    return evaluate(merged, "example.Configuration", null);
}
