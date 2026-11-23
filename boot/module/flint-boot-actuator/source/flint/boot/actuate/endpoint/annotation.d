// Ported from spring-boot v4.2.0: module/spring-boot-actuator/src/main/java/org/springframework/boot/actuate/endpoint/annotation/Endpoint.java
// with ReadOperation.java and Selector.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: annotations are UDA structs (rulebook R2). Flint does not discover annotated
// endpoints at runtime yet: an endpoint's web operations are registered as `ExposableWebEndpoint` beans
// (flint.boot.actuate.endpoint.web), which Flint AOT will generate from these annotations.

/// `org.springframework.boot.actuate.endpoint.annotation`: the endpoint annotations.
module flint.boot.actuate.endpoint.annotation;

@safe:

/// Marks a bean as an actuator endpoint.
struct Endpoint
{
    /// The endpoint's id.
    string id;
}

/// Marks an endpoint method as a read operation.
struct ReadOperation
{
    /// The media types the operation produces.
    string[] produces;
}

/// Marks an operation parameter as part of the operation's path.
struct Selector
{
    /// How the selector matches.
    enum Match
    {
        /// One path segment.
        SINGLE,
        /// The remaining path segments.
        ALL_REMAINING
    }

    /// How the selector matches.
    Match match = Match.SINGLE;
}
