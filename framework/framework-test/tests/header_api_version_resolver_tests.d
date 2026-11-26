/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/web/accept/HeaderApiVersionResolverTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: use named D unittests and Nullable for R5.
+/
module header_api_version_resolver_tests;

import flint.mock.web : MockHttpServletRequest;
import flint.web.accept : ApiVersionResolver, HeaderApiVersionResolver;

@safe:

@("resolve")
unittest
{
    ApiVersionResolver resolver = new HeaderApiVersionResolver("Api-Version");
    auto request = new MockHttpServletRequest("GET", "/path");
    request.addHeader("Api-Version", "1.2");

    const actual = resolver.resolveVersion(request);
    assert(!actual.isNull && actual.get == "1.2");
}

@("noHeader")
unittest
{
    auto resolver = new HeaderApiVersionResolver("Api-Version");
    auto request = new MockHttpServletRequest("GET", "/path");

    assert(resolver.resolveVersion(request).isNull);
}

@("Header version resolution preserves an empty first value")
unittest
{
    auto resolver = new HeaderApiVersionResolver("Api-Version");
    auto request = new MockHttpServletRequest("GET", "/path");
    request.addHeader("api-version", "");
    request.addHeader("Api-Version", "1.2");

    const actual = resolver.resolveVersion(request);
    assert(!actual.isNull && actual.get.length == 0);
}
