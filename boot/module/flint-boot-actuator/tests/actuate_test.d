// Ported from spring-boot v4.2.0: module/spring-boot-actuator/src/test/java/org/springframework/boot/actuate/endpoint/web/LinkTests.java
// with EndpointLinksResolverTests.java and EndpointMappingTests.java from the same directory, ../EndpointIdTests.java and
// module/spring-boot-actuator-autoconfigure/src/test/java/org/springframework/boot/actuate/autoconfigure/endpoint/expose/IncludeExcludeEndpointFilterTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: endpoints are `ExposableWebEndpoint`s built in the test.
module actuate_test;

import flint.boot.actuate.autoconfigure.endpoint.web : IncludeExcludeEndpointFilter, WebEndpointProperties;
import flint.boot.actuate.endpoint : EndpointId;
import flint.boot.actuate.endpoint.web;

@safe:

private final class TestEndpoint : ExposableWebEndpoint
{
    EndpointId getEndpointId()
    {
        return EndpointId.of("health");
    }

    string getRootPath()
    {
        return "health";
    }

    WebOperation[] getOperations()
    {
        return [cast(WebOperation) new Op("health", "health"), new Op("health-path", "health/{*path}")];
    }

    private static final class Op : WebOperation
    {
        string id, path;

        this(string id, string path)
        {
            this.id = id;
            this.path = path;
        }

        string getId()
        {
            return id;
        }

        WebOperationRequestPredicate getRequestPredicate()
        {
            return new WebOperationRequestPredicate(path, WebEndpointHttpMethod.GET, null, [
                "application/json"
            ]);
        }

        WebEndpointResponse invoke(string[])
        {
            return new WebEndpointResponse(imported!"flint.engine.aot.any".Any.init);
        }
    }
}

@("LinkTests: a link is templated when its href has a variable") unittest
{
    assert(!new Link("https://example.com").isTemplated());
    assert(new Link("https://example.com/{path}").isTemplated());
}

@("EndpointLinksResolverTests: self first, then each operation; a trailing slash is removed") unittest
{
    auto links = new EndpointLinksResolver([cast(ExposableWebEndpoint) new TestEndpoint]).resolveLinks(
            "https://api.example.com/actuator/");
    assert(links.keySet().toArray() == ["self", "health", "health-path"]);
    assert(links.get("self").getHref() == "https://api.example.com/actuator");
    assert(links.get("health").getHref() == "https://api.example.com/actuator/health");
    assert(links.get("health-path").getHref() == "https://api.example.com/actuator/health/{*path}");
    assert(links.get("health-path").isTemplated());
}

@("EndpointMappingTests: normalized base paths and sub-paths") unittest
{
    assert(new EndpointMapping("actuator/").getPath() == "/actuator");
    assert(new EndpointMapping("/actuator").createSubPath("health") == "/actuator/health");
    assert(new EndpointMapping("").createSubPath("/health") == "/health");
    assert(new EndpointMapping("/").getPath() == "");
}

@("EndpointIdTests: lower-case form, equality ignoring dashes and case, invalid ids") unittest
{
    import flint.java.lang : IllegalArgumentException;

    assert(EndpointId.of("fooBar").toLowerCaseString() == "foobar");
    assert(EndpointId.of("foo-bar") == EndpointId.of("fooBar"));
    foreach (bad; ["", "Foo", "foo bar"])
    {
        bool thrown;
        try
            EndpointId.of(bad);
        catch (IllegalArgumentException)
            thrown = true;
        assert(thrown, bad);
    }
}

@("IncludeExcludeEndpointFilterTests: defaults, *, and exclude winning") unittest
{
    auto defaults = new IncludeExcludeEndpointFilter(null, null, "health");
    assert(defaults.match("health") && !defaults.match("info"));
    auto all = new IncludeExcludeEndpointFilter(["*"], ["env"], "health");
    assert(all.match("info") && !all.match("env"));
    assert(new IncludeExcludeEndpointFilter(["info"], null, "health").match("INFO"));
}

@("WebEndpointProperties: Boot's defaults") unittest
{
    auto properties = new WebEndpointProperties;
    assert(properties.getBasePath() == "/actuator");
    assert(properties.getExposure().getInclude() is null && properties.getExposure().getExclude() is null);
    assert(properties.getDiscovery().isEnabled());
}
