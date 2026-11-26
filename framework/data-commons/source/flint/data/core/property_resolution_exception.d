// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/core/PropertyResolutionException.java
// Copyright 2026-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.core.property_resolution_exception;

import flint.core : NestedRuntimeException;

@safe:

/// Indicates a failure to resolve a property reference or path.
class PropertyResolutionException : NestedRuntimeException
{
    /// Constructs the exception with a detail message and optional nested cause.
    this(string message, Throwable cause = null) pure nothrow
    {
        super(message, cause);
    }
}
