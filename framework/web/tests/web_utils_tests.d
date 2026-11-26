/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/web/util/WebUtilsTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: Java Object map values use Any (R23).
+/
module flint.web.web_utils_tests;

import flint.engine.aot.any : Any;
import flint.jakarta.servlet : ServletException;
import flint.java.util : HashMap;
import flint.web : HttpSessionRequiredException;
import flint.web.util : WebUtils;

@safe:

@("WebUtilsTests.findParameterValue")
unittest
{
    auto params = new HashMap!(string, Any);
    params.put("myKey1", Any.of("myValue1"));
    params.put("myKey2_myValue2", Any.of("xxx"));
    params.put("myKey3_myValue3.x", Any.of("xxx"));
    params.put("myKey4_myValue4.y", Any.of(["yyy"]));

    assert(WebUtils.findParameterValue(params, "myKey0").isNull);
    assert(WebUtils.findParameterValue(params, "myKey1").get == "myValue1");
    assert(WebUtils.findParameterValue(params, "myKey2").get == "myValue2");
    assert(WebUtils.findParameterValue(params, "myKey3").get == "myValue3");
    assert(WebUtils.findParameterValue(params, "myKey4").get == "myValue4");
}

@("Flint.WebUtils.directParameterPrecedesSubmitButton")
unittest
{
    auto params = new HashMap!(string, Any);
    params.put("submit_image.x", Any.of("10"));
    params.put("submit", Any.of(["direct", "second"]));
    assert(WebUtils.findParameterValue(params, "submit").get == "direct");

    params.put("submit", Any.of([cast(string) null]));
    assert(WebUtils.findParameterValue(params, "submit").isNull);

    params.put("submit", Any.of(7));
    assert(WebUtils.findParameterValue(params, "submit").get == "7");

    params.remove("submit");
    assert(WebUtils.findParameterValue(params, "submit").get == "image");
}

@("Flint.HttpSessionRequiredException.preservesExpectedAttribute")
unittest
{
    auto missingSession = new HttpSessionRequiredException("No session");
    auto missingAttribute = new HttpSessionRequiredException("No active cart", "cart");
    ServletException servletException = missingAttribute;
    assert(missingSession.getMessage() == "No session");
    assert(missingSession.getExpectedAttribute().isNull);
    assert(servletException.getMessage() == "No active cart");
    assert(servletException.getRootCause() is null);
    assert(missingAttribute.getExpectedAttribute().get == "cart");
    assert((new HttpSessionRequiredException("Empty name", "")).getExpectedAttribute().get == "");
}
