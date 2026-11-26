// Ported from spring-framework v7.1.0: spring-context/src/test/java/org/springframework/validation/DataBinderTests.java
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.binding_result_utils_test;

import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, IllegalStateException;
import flint.java.util : HashMap;
import flint.validation : BindingResult, BindingResultUtils, MapBindingResult;
import std.exception : assertThrown;

@safe:

@("DataBinderTests.bindingWithErrors: model lookup")
unittest
{
    auto target = new HashMap!(string, Any);
    auto result = new MapBindingResult(target, "person");
    auto model = new HashMap!(string, Any);
    model.put("person", Any.of(target));
    model.put(BindingResult.MODEL_KEY_PREFIX ~ "person", Any.of(result));

    assert(BindingResultUtils.getBindingResult(model, "person") is result);
    assert(BindingResultUtils.getRequiredBindingResult(model, "person") is result);
    assert(BindingResultUtils.getBindingResult(model, "someOtherName") is null);
    assertThrown!IllegalStateException(BindingResultUtils.getRequiredBindingResult(model, "someOtherName"));
}

@("binding result lookup distinguishes null attributes from values of the wrong type")
unittest
{
    auto model = new HashMap!(string, Any);
    const key = BindingResult.MODEL_KEY_PREFIX ~ "person";
    model.put(key, Any.init);
    assert(BindingResultUtils.getBindingResult(model, "person") is null);

    model.put(key, Any.of("unexpected"));
    string message;
    try
        BindingResultUtils.getBindingResult(model, "person");
    catch (IllegalStateException error)
        message = error.getMessage();
    assert(message == "BindingResult attribute is not of type BindingResult: unexpected");

    assertThrown!IllegalArgumentException(BindingResultUtils.getBindingResult(null, "person"));
    assertThrown!IllegalArgumentException(BindingResultUtils.getBindingResult(model, null));
}

@("binding result lookup supports typed maps and misses incompatible keys")
unittest
{
    auto target = new HashMap!(string, Any);
    auto result = new MapBindingResult(target, "person");
    auto typed = new HashMap!(string, BindingResult);
    typed.put(BindingResult.MODEL_KEY_PREFIX ~ "person", result);
    assert(BindingResultUtils.getBindingResult(typed, "person") is result);

    auto numeric = new HashMap!(int, BindingResult);
    numeric.put(1, result);
    assert(BindingResultUtils.getBindingResult(numeric, "person") is null);
}
