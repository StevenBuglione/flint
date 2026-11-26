/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/web/accept/QueryApiVersionResolverTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: use named D unittests and Nullable for R5.
+/
module query_api_version_resolver_tests;

import flint.mock.web : MockHttpServletRequest;
import flint.web.accept : ApiVersionResolver, QueryApiVersionResolver;

@safe:

private MockHttpServletRequest requestWithQuery(string query)
{
    auto request = new MockHttpServletRequest("GET", "/path");
    request.setQueryString(query);
    return request;
}

@("resolve")
unittest
{
    ApiVersionResolver resolver = new QueryApiVersionResolver("api-version");
    const result = resolver.resolveVersion(requestWithQuery("q=foo&api-version=1.2"));
    assert(!result.isNull && result.get == "1.2");
}

@("noQueryString")
unittest
{
    auto resolver = new QueryApiVersionResolver("api-version");
    assert(resolver.resolveVersion(requestWithQuery(null)).isNull);
}

@("noQueryParam")
unittest
{
    auto resolver = new QueryApiVersionResolver("api-version");
    auto request = requestWithQuery("q=foo");
    request.addParameter("api-version", "form");
    assert(resolver.resolveVersion(request).isNull);
}

@("Query version resolution preserves raw values and the first occurrence")
unittest
{
    auto resolver = new QueryApiVersionResolver("api-version");
    const raw = resolver.resolveVersion(requestWithQuery("api-version=1%2E2+rc&api-version=2"));
    assert(!raw.isNull && raw.get == "1%2E2+rc");
    assert(resolver.resolveVersion(requestWithQuery("api-version&api-version=2")).isNull);

    const empty = resolver.resolveVersion(requestWithQuery("api-version=&api-version=2"));
    assert(!empty.isNull && empty.get.length == 0);
}

@("Query version resolution follows Spring's delimiters")
unittest
{
    auto resolver = new QueryApiVersionResolver("api-version");
    const result = resolver.resolveVersion(requestWithQuery("==api-version=1=2#api-version=3"));
    assert(!result.isNull && result.get == "1=2");
    assert(resolver.resolveVersion(requestWithQuery("q=foo#api-version=3")).isNull);

    auto blankName = new QueryApiVersionResolver(" ");
    assert(blankName.resolveVersion(requestWithQuery(" #fragment")).isNull);
}
