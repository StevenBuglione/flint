/++
Ported from spring-projects/spring-framework v7.1.0,
spring-webmvc/src/test/java/org/springframework/web/servlet/resource/
(ResourceHandlerUtilsTests.java, PathResourceResolverTests.java).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: class-path test files are embedded in the test fixture.
+/
module flint.web.servlet.resource_resolution_tests;

import flint.core.io : ClassPathResource, FileSystemResource, Resource, installEmbeddedResources,
    installedEmbeddedResources;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : List;
import flint.web.servlet.resource : PathResourceResolver, ResourceHandlerUtils;

@safe:

private enum root = "org/springframework/web/servlet/resource/";

private immutable(ubyte)[] fixture(string path) nothrow
{
    switch (path)
    {
    case root ~ "test/bar.css":
    case root ~ "test/main.css":
    case root ~ "testalternatepath/bar.css":
        return cast(
                immutable(ubyte)[]) "h1 { color:red; }";
    default:
        return null;
    }
}

private void expectsBadLocation(Resource location, string message)
{
    try
        ResourceHandlerUtils.assertResourceLocation(location);
    catch (IllegalArgumentException e)
    {
        import std.algorithm.searching : canFind;

        assert(e.getMessage().canFind(message));
        return;
    }
    assert(false, "expected IllegalArgumentException");
}

@("Flint.ResourceHandlerUtils.assertSupportedLocations")
unittest
{
    ResourceHandlerUtils.assertResourceLocation(new ClassPathResource("test/"));
    ResourceHandlerUtils.assertResourceLocation(new FileSystemResource("test/"));
}

@("ResourceHandlerUtilsTests.assertResourceLocationShouldRejectNull")
unittest
{
    expectsBadLocation(null, "Resource location must not be null");
}

@("ResourceHandlerUtilsTests.assertResourceLocationShouldRejectNotEndWithSlash")
unittest
{
    expectsBadLocation(new ClassPathResource("test"), "Resource location does not end with slash");
}

@("ResourceHandlerUtilsTests.assertResourceLocationShouldRejectUnsafeClassPathResource")
unittest
{
    expectsBadLocation(new ClassPathResource(""), "is considered unsafe");
    expectsBadLocation(new ClassPathResource("/"), "is considered unsafe");
}

@("Flint.ResourceHandlerUtils.normalizeAndValidate")
unittest
{
    assert(ResourceHandlerUtils.normalizeInputPath("  / // foo\\bar") == "/foo/bar");
    assert(ResourceHandlerUtils.normalizeInputPath("assets//café.css") == "assets/café.css");
    assert(ResourceHandlerUtils.normalizeInputPath("///") == "/");
    assert(ResourceHandlerUtils.initLocationPath("assets/test") == "assets/test/");
    assert(ResourceHandlerUtils.initLocationPath("assets\\test") == "assets\\test\\");
    assert(!ResourceHandlerUtils.shouldIgnoreInputPath("assets/caf%C3%A9.css"));
    assert(ResourceHandlerUtils.shouldIgnoreInputPath(" "));
    assert(ResourceHandlerUtils.shouldIgnoreInputPath("assets/META-INF/config.txt"));
    assert(ResourceHandlerUtils.shouldIgnoreInputPath("assets/../config.txt"));
    assert(ResourceHandlerUtils.shouldIgnoreInputPath("assets/bad%file.txt"));
}

@("PathResourceResolverTests.resolveFromClasspath")
unittest
{
    const previous = installedEmbeddedResources();
    installEmbeddedResources(&fixture);
    scope (exit)
        installEmbeddedResources(previous);

    Resource location = new ClassPathResource(root ~ "test/");
    auto resolver = new PathResourceResolver();
    auto result = resolver.resolveResource(null, "bar.css", List!Resource.of(location), null);
    assert(result !is null && result.getFilename() == "bar.css");
    assert((cast(ClassPathResource) result).getPath() == root ~ "test/bar.css");
}

@("PathResourceResolverTests.resolveFromClasspathRoot")
unittest
{
    const previous = installedEmbeddedResources();
    installEmbeddedResources(&fixture);
    scope (exit)
        installEmbeddedResources(previous);

    auto resolver = new PathResourceResolver();
    auto result = resolver.resolveResource(null, root ~ "test/bar.css",
            List!Resource.of(new ClassPathResource("/")), null);
    assert(result !is null);
}

@("PathResourceResolverTests.checkResourceWithAllowedLocations")
unittest
{
    const previous = installedEmbeddedResources();
    installEmbeddedResources(&fixture);
    scope (exit)
        installEmbeddedResources(previous);

    auto resolver = new PathResourceResolver();
    auto locations = List!Resource.of(new ClassPathResource(root ~ "test/main.css"));
    const url = "../testalternatepath/bar.css";
    assert(resolver.resolveUrlPath(url, locations, null).isNull);
    resolver.setAllowedLocations(new ClassPathResource(root ~ "test/"),
            new ClassPathResource(root ~ "testalternatepath/"));
    assert(resolver.resolveUrlPath(url, locations, null).get() == url);
}

private final class ExposedResolver : PathResourceResolver
{
    bool under(Resource resource, Resource location)
    {
        return checkResource(resource, location);
    }
}

@("PathResourceResolverTests.checkFileLocation")
unittest
{
    const path = root ~ "test/main.css";
    assert(new ExposedResolver().under(new ClassPathResource(path), new ClassPathResource(path)));
}

@("PathResourceResolverTests.resolvePathRootResource")
unittest
{
    auto resolver = new PathResourceResolver();
    auto locations = List!Resource.of(new ClassPathResource("/META-INF/resources/webjars/"));
    assert(resolver.resolveUrlPath("", locations, null).isNull);
}

@("Flint.PathResourceResolver.containment")
unittest
{
    auto resolver = new ExposedResolver();
    auto location = new FileSystemResource("public/site/");
    assert(resolver.under(new FileSystemResource("public/site/main.css"), location));
    assert(!resolver.under(new FileSystemResource("public/site-private/main.css"), location));
    assert(!resolver.under(new ClassPathResource("public/site/main.css"), location));
}
