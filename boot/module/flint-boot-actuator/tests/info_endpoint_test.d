// Ported from spring-boot v4.2.0: module/spring-boot-actuator/src/test/java/org/springframework/boot/actuate/info/InfoEndpointTests.java
// Ported from spring-boot v4.2.0: module/spring-boot-actuator/src/test/java/org/springframework/boot/actuate/info/InfoTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors.
module info_endpoint_test;

import flint.boot.actuate.info : Info, InfoContributor, InfoEndpoint;
import flint.java.lang : IllegalArgumentException, UnsupportedOperationException;
import flint.java.util : List;
import std.exception : assertThrown;

@safe:

private alias Contribution = void delegate(Info.Builder) @safe;

@("InfoEndpointTests.info")
unittest
{
    Contribution[] contributors = [
        (Info.Builder builder) { builder.withDetail("key1", "value1"); }, (Info.Builder builder) {
            builder.withDetail("key2", "value2");
        }
    ];
    auto endpoint = new InfoEndpoint(contributors);
    auto details = endpoint.info();
    assert(details.size() == 2);
    assert(details.get("key1").get!string() == "value1");
    assert(details.get("key2").get!string() == "value2");
}

@("InfoEndpointTests.infoWithNoContributorsProducesEmptyMap")
unittest
{
    auto endpoint = new InfoEndpoint(List!InfoContributor.of());
    assert(endpoint.info().isEmpty());
}

@("InfoTests.infoIsImmutable")
unittest
{
    auto info = new Info.Builder().withDetail("foo", "bar").build();
    assertThrown!UnsupportedOperationException(info.getDetails().clear());
}

@("InfoTests.infoTakesCopyOfMap")
unittest
{
    auto builder = new Info.Builder();
    builder.withDetail("foo", "bar");
    auto info = builder.build();
    builder.withDetail("biz", "bar");
    assert(info.getDetails().size() == 1);
    assert(info.getDetails().get("foo").get!string() == "bar");
}

@("InfoEndpoint rejects null contributor lists")
unittest
{
    assertThrown!IllegalArgumentException(new InfoEndpoint(cast(List!InfoContributor) null));
    assert(new InfoEndpoint(cast(Contribution[]) null).info().isEmpty());
}
