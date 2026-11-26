/++
Adapted scenario from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/web/accept/ContentNegotiationManagerFactoryBeanTests.java.
Copyright 2002-present the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: exercise extension aggregation directly through the manager.
+/
module flint.web.content_negotiation_extension_tests;

import flint.http : MediaType;
import flint.java.util : Collections, List;
import flint.web.accept : ContentNegotiationManager, FixedContentNegotiationStrategy, MediaTypeFileExtensionResolver;

@safe:

private final class ExtensionStrategy : FixedContentNegotiationStrategy, MediaTypeFileExtensionResolver
{
    private List!string extensions;
    int lookupCalls;
    int listCalls;

    this(string[] extensions...)
    {
        super(MediaType.APPLICATION_JSON);
        this.extensions = List!string.of(extensions);
    }

    List!string resolveFileExtensions(MediaType mediaType)
    {
        ++lookupCalls;
        return mediaType == MediaType.APPLICATION_JSON ? extensions : Collections.emptyList!string();
    }

    List!string getAllFileExtensions()
    {
        ++listCalls;
        return extensions;
    }
}

@("Flint: manager collects extension resolvers once in registration order")
unittest
{
    auto first = new ExtensionStrategy("json", "js");
    auto second = new ExtensionStrategy("json", "jsonl");
    auto manager = new ContentNegotiationManager(first, first);
    manager.addFileExtensionResolvers(second, first);

    auto extensions = manager.resolveFileExtensions(MediaType.APPLICATION_JSON);
    assert(extensions.toArray() == ["json", "js", "jsonl"]);
    assert(first.lookupCalls == 1 && second.lookupCalls == 1);
    assert(manager.getAllFileExtensions().toArray() == ["json", "js", "jsonl"]);
    assert(first.listCalls == 1 && second.listCalls == 1);
    assert(manager.resolveFileExtensions(MediaType.IMAGE_GIF).isEmpty());
}

@("Flint: extension results are detached and an unconfigured manager returns empty lists")
unittest
{
    auto manager = new ContentNegotiationManager();
    assert(manager.getAllFileExtensions().isEmpty());
    assert(manager.resolveFileExtensions(MediaType.APPLICATION_JSON).isEmpty());

    auto resolver = new ExtensionStrategy("json");
    manager.addFileExtensionResolvers(resolver);
    auto extensions = manager.getAllFileExtensions();
    extensions.set(0, "changed");
    assert(manager.getAllFileExtensions().toArray() == ["json"]);
    assert(resolver.getAllFileExtensions().toArray() == ["json"]);
}
