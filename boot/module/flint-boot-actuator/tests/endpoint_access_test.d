// Ported from spring-boot v4.2.0: module/spring-boot-actuator/src/test/java/org/springframework/boot/actuate/endpoint/AccessTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors.
module endpoint_access_test;

import flint.boot.actuate.endpoint : Access, cap;
import flint.boot.actuate.endpoint.annotation : Endpoint;

@safe:

@("capWhenAboveMaximum")
unittest
{
    assert(Access.UNRESTRICTED.cap(Access.READ_ONLY) == Access.READ_ONLY);
}

@("capWhenAtMaximum")
unittest
{
    assert(Access.READ_ONLY.cap(Access.READ_ONLY) == Access.READ_ONLY);
}

@("capWhenBelowMaximum")
unittest
{
    assert(Access.NONE.cap(Access.READ_ONLY) == Access.NONE);
}

@("a null maximum is rejected at compile time")
unittest
{
    static assert(!__traits(compiles, Access.UNRESTRICTED.cap(null)));
}

@("endpoint annotations carry typed default access")
unittest
{
    @Endpoint("default")
    struct DefaultEndpoint
    {
    }

    @Endpoint(id: "read-only", defaultAccess: Access.READ_ONLY)
    struct ReadOnlyEndpoint
    {
    }

    enum implicit = __traits(getAttributes, DefaultEndpoint)[0];
    enum explicit = __traits(getAttributes, ReadOnlyEndpoint)[0];
    static assert(implicit.id == "default" && implicit.defaultAccess == Access.UNRESTRICTED);
    static assert(explicit.id == "read-only" && explicit.defaultAccess == Access.READ_ONLY);
    static assert(is(typeof(explicit.defaultAccess) == Access));

    static assert(!__traits(compiles, () {
            import flint.boot.actuate.endpoint.annotation : AnnotationAccess = Access;

            return AnnotationAccess.READ_ONLY;
        }()));
}
