// Ported from spring-boot v4.2.0: module/spring-boot-actuator/src/test/java/org/springframework/boot/actuate/endpoint/AccessTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors.
module endpoint_access_test;

import flint.boot.actuate.endpoint : Access, cap;
import flint.java.lang : IllegalArgumentException;
import std.exception : assertThrown;

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

@("a null maximum is rejected")
unittest
{
    assertThrown!IllegalArgumentException(Access.UNRESTRICTED.cap(null));
}
