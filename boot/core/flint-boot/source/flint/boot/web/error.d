// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/web/error/ErrorAttributeOptions.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the `EnumSet` is a bit set; `Map<String, Object>` is `flint.java.util.Map!(string, V)` with `V` `Object` or `Any`.

/// `org.springframework.boot.web.error`: which attributes an error response includes.
module flint.boot.web.error;

import flint.java.util : Map;

@safe:

/// The attributes `ErrorAttributes` includes in an error response.
final class ErrorAttributeOptions
{
    /// An attribute of an error response.
    enum Include
    {
        /// `exception`: the exception's class name.
        EXCEPTION,
        /// `trace`: the stack trace.
        STACK_TRACE,
        /// `message`: the exception or error message.
        MESSAGE,
        /// `errors`: binding errors.
        BINDING_ERRORS,
        /// `status`: the HTTP status code.
        STATUS,
        /// `error`: the status reason phrase.
        ERROR,
        /// `path`: the request path.
        PATH
    }

    private static immutable string[] keys = [
        "exception", "trace", "message", "errors", "status", "error", "path"
    ];

    private uint includes;

    private this(uint includes) pure nothrow @nogc
    {
        this.includes = includes;
    }

    /// The attribute key of `include` (`STACK_TRACE` is `trace`, `BINDING_ERRORS` is `errors`).
    static string key(Include include) pure nothrow @nogc
    {
        return keys[include];
    }

    /// Whether `include` is included.
    bool isIncluded(Include include) const pure nothrow @nogc
    {
        return (includes & (1u << include)) != 0;
    }

    /// The included attributes, in declaration order.
    Include[] getIncludes() const pure nothrow
    {
        Include[] result;
        foreach (index; 0 .. keys.length)
        {
            if (includes & (1u << index))
                result ~= cast(Include) index;
        }
        return result;
    }

    /// A copy that also includes `added`.
    ErrorAttributeOptions including(Include[] added...) const pure nothrow
    {
        uint updated = includes;
        foreach (include; added)
            updated |= 1u << include;
        return new ErrorAttributeOptions(updated);
    }

    /// A copy without `removed`.
    ErrorAttributeOptions excluding(Include[] removed...) const pure nothrow
    {
        uint updated = includes;
        foreach (include; removed)
            updated &= ~(1u << include);
        return new ErrorAttributeOptions(updated);
    }

    /// Remove from `map` the keys of the attributes that are not included. `V` is `Object`, or `Any` for the
    /// attribute maps of Flint's web layer.
    void retainIncluded(V)(Map!(string, V) map) const
    {
        foreach (index, attributeKey; keys)
        {
            if (!(includes & (1u << index)))
                map.remove(attributeKey);
        }
    }

    /// `PATH`, `STATUS` and `ERROR`: Boot's defaults.
    static ErrorAttributeOptions defaults() pure nothrow
    {
        return of(Include.PATH, Include.STATUS, Include.ERROR);
    }

    /// Options including exactly `included`.
    static ErrorAttributeOptions of(Include[] included...) pure nothrow
    {
        return new ErrorAttributeOptions(0).including(included);
    }
}
