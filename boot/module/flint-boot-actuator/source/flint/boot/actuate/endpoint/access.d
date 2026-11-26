// Ported from spring-boot v4.2.0: module/spring-boot-actuator/src/main/java/org/springframework/boot/actuate/endpoint/Access.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors.

/// Internal R1 leaf for the endpoint annotation. Applications import Access from flint.boot.actuate.endpoint.
module flint.boot.actuate.endpoint.access;

@safe:

/// Access to an endpoint and its operations, ordered from least to most permissive.
enum Access
{
    /// No access to the endpoint.
    NONE,
    /// Access to read operations.
    READ_ONLY,
    /// Access to all operations.
    UNRESTRICTED
}
