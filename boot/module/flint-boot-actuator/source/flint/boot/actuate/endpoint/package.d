// Ported from spring-boot v4.2.0: module/spring-boot-actuator/src/main/java/org/springframework/boot/actuate/endpoint/ApiVersion.java
// with Access.java, EndpointId.java, OperationResponseBody.java, OperationType.java and SecurityContext.java from the same
// directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `ApiVersion`'s `MimeType` is its media type text; `SecurityContext` has no
// principal until Flint Security joins.

/// `org.springframework.boot.actuate.endpoint`: actuator endpoints.
module flint.boot.actuate.endpoint;

import flint.java.lang : IllegalArgumentException;

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

/// Limit the access to the configured maximum (R20).
Access cap(Access access, Access maxPermitted) pure nothrow @nogc
{
    return access <= maxPermitted ? access : maxPermitted;
}

/// Preserve the null argument exception of Java's Access.cap.
Access cap(Access, typeof(null))
{
    throw new IllegalArgumentException("'maxPermitted' must not be null");
}

/// The version of the actuator's API, and the media type it produces.
enum ApiVersion
{
    /// `application/vnd.spring-boot.actuator.v2+json`.
    V2,
    /// `application/vnd.spring-boot.actuator.v3+json`.
    V3
}

/// The latest API version.
enum ApiVersion LATEST_API_VERSION = ApiVersion.V3;

/// The media type `version` produces (Java's `getProducedMimeType()`).
string getProducedMimeType(ApiVersion version_) pure nothrow @nogc
{
    return version_ == ApiVersion.V2
        ? "application/vnd.spring-boot.actuator.v2+json" : "application/vnd.spring-boot.actuator.v3+json";
}

/// Marks a type an operation returns as its response body.
interface OperationResponseBody
{
}

/// The kind of an operation.
enum OperationType
{
    /// A read (HTTP GET).
    READ,
    /// A write (HTTP POST).
    WRITE,
    /// A delete (HTTP DELETE).
    DELETE
}

/// An endpoint's identifier: letters and digits, starting lower case.
final class EndpointId
{
    private string value;
    private string lowerCaseValue;

    private this(string value) pure
    {
        import std.uni : toLower;

        this.value = value;
        lowerCaseValue = value.toLower;
    }

    /// The id `value`. Throws `IllegalArgumentException` when it is empty or has other characters.
    static EndpointId of(string value)
    {
        import flint.java.lang : IllegalArgumentException;
        import std.ascii : isAlphaNum, isLower;

        if (value.length == 0)
            throw new IllegalArgumentException("'value' must not be empty");
        foreach (c; value)
        {
            if (!isAlphaNum(c) && c != '.' && c != '-')
                throw new IllegalArgumentException("'value' must only contain valid chars");
        }
        if (!isLower(value[0]) && !(value[0] >= '0' && value[0] <= '9'))
            throw new IllegalArgumentException("'value' must start with a lowercase letter");
        return new EndpointId(value);
    }

    /// The id in lower case.
    string toLowerCaseString() const pure nothrow @nogc
    {
        return lowerCaseValue;
    }

    /// The id.
    override string toString() const pure nothrow @nogc
    {
        return value;
    }

    /// Ids are equal ignoring case and dashes and dots, as Boot compares them.
    override bool opEquals(Object other) const
    {
        auto id = cast(const EndpointId) other;
        return id !is null && alphaNumeric() == id.alphaNumeric();
    }

    /// Consistent with `opEquals`.
    override size_t toHash() const nothrow @safe
    {
        return hashOf(alphaNumeric());
    }

    private string alphaNumeric() const pure nothrow
    {
        import std.ascii : isAlphaNum;

        string result;
        foreach (c; lowerCaseValue)
        {
            if (isAlphaNum(c))
                result ~= c;
        }
        return result;
    }
}

/// The security context an operation runs in.
final class SecurityContext
{
    /// No principal and no roles.
    static immutable SecurityContext NONE = new immutable SecurityContext;

    /// Whether the principal has `role`; always false until Flint Security joins.
    bool isUserInRole(string) const pure nothrow @nogc
    {
        return false;
    }
}
