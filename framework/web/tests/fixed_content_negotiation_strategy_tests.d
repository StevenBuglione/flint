/++
Adapted scenarios from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/web/accept/ContentNegotiationManagerFactoryBeanTests.java.
Copyright 2002-present the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: exercise the fixed strategy directly and through the manager.
+/
module flint.web.fixed_content_negotiation_strategy_tests;

import flint.http : MediaType;
import flint.java.lang : IllegalArgumentException, UnsupportedOperationException;
import flint.java.util : List;
import flint.web.accept : ContentNegotiationManager, FixedContentNegotiationStrategy;

@safe:

@("Flint: fixed negotiation supplies an ordered default after wildcard preferences")
unittest
{
    auto defaults = List!MediaType.of(MediaType.APPLICATION_JSON, MediaType.ALL);
    auto strategy = new FixedContentNegotiationStrategy(defaults);
    auto wildcard = new FixedContentNegotiationStrategy(MediaType.ALL);
    auto manager = new ContentNegotiationManager(wildcard, strategy);

    assert(manager.resolveMediaTypes(null) == [MediaType.APPLICATION_JSON, MediaType.ALL]);
    auto explicitPreference = new FixedContentNegotiationStrategy(MediaType.IMAGE_GIF);
    manager = new ContentNegotiationManager(explicitPreference, strategy);
    assert(manager.resolveMediaTypes(null) == [MediaType.IMAGE_GIF]);
}

@("Flint: fixed negotiation protects its configured defaults from mutation through results")
unittest
{
    auto strategy = new FixedContentNegotiationStrategy(MediaType.APPLICATION_JSON);
    auto resolved = strategy.resolveMediaTypes(null);
    resolved[0] = MediaType.IMAGE_GIF;
    assert(strategy.resolveMediaTypes(null) == [MediaType.APPLICATION_JSON]);

    try
        strategy.getContentTypes().set(0, MediaType.IMAGE_GIF);
    catch (UnsupportedOperationException)
    {
        assert(strategy.getContentTypes().get(0) == MediaType.APPLICATION_JSON);
        return;
    }
    assert(false, "Expected the configured list to reject mutation");
}

@("Flint: fixed negotiation rejects a null default list")
unittest
{
    try
        new FixedContentNegotiationStrategy(cast(List!MediaType) null);
    catch (IllegalArgumentException)
        return;
    assert(false, "Expected a null list to fail");
}
