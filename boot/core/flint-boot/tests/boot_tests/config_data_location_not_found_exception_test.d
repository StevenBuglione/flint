// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/config/
// ConfigDataLocationNotFoundExceptionTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; one unittest per upstream @Test; a
// `ConfigDataLocation` is a struct, compared by value.
// Not ported: createWhenLocationIsNullThrowsException (a struct location cannot be null).
module boot_tests.config_data_location_not_found_exception_test;

import flint.boot.context.config : ConfigDataLocation, ConfigDataLocationNotFoundException;

@safe:

private ConfigDataLocation location()
{
    return ConfigDataLocation.of("optional:test");
}

@("getLocationReturnsLocation") unittest
{
    auto exception = new ConfigDataLocationNotFoundException(location());
    assert(exception.getLocation() == location());
}

version (FlintConfigDataLocationApi)
{
    // Gap: locations carry no origin, and the exception has no getOrigin or getReferenceDescription.
    import flint.boot.origin : TextResourceOrigin;

    @("getOriginReturnsLocationOrigin") unittest
    {
        auto origin = new TextResourceOrigin("test", 1, 1);
        auto exception = new ConfigDataLocationNotFoundException(location().withOrigin(origin));
        assert(exception.getOrigin() is origin);
    }

    @("getReferenceDescriptionReturnsLocationString") unittest
    {
        auto exception = new ConfigDataLocationNotFoundException(location());
        assert(exception.getReferenceDescription() == "location 'optional:test'");
    }
}

@("getMessageReturnsMessage") unittest
{
    auto exception = new ConfigDataLocationNotFoundException(location());
    assert(exception.msg == "Config data location 'optional:test' cannot be found");
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
