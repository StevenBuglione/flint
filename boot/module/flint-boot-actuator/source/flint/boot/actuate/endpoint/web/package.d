// Ported from spring-boot v4.2.0: module/spring-boot-actuator/src/main/java/org/springframework/boot/actuate/endpoint/web/Link.java
// with WebEndpointResponse.java, EndpointLinksResolver.java, EndpointMapping.java, WebOperation.java,
// WebOperationRequestPredicate.java, WebEndpointHttpMethod.java and ExposableWebEndpoint.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `WebEndpointResponse<T>` is erased (R12) with an `Any` body; an operation is invoked
// with its selector values (`invoke(string[] selectors)`), since Flint registers web operations explicitly instead
// of discovering annotated methods; `MimeType`s are their text.

/// `org.springframework.boot.actuate.endpoint.web`: actuator endpoints over HTTP.
module flint.boot.actuate.endpoint.web;

import flint.boot.actuate.endpoint : EndpointId;
import flint.engine.aot.any : Any;
import flint.java.util : LinkedHashMap;

@safe:

/// A link to an endpoint operation, as the links resource lists it.
class Link
{
    private string href;
    private bool templated;

    /// A link to `href`, templated when it contains `{`.
    this(string href)
    {
        import flint.java.lang : IllegalArgumentException;
        import std.algorithm.searching : canFind;

        if (href is null)
            throw new IllegalArgumentException("'href' must not be null");
        this.href = href;
        this.templated = href.canFind('{');
    }

    /// The link's target.
    string getHref() const pure nothrow @nogc
    {
        return href;
    }

    /// Whether the target is a URI template.
    bool isTemplated() const pure nothrow @nogc
    {
        return templated;
    }

    /// `[href=...]`.
    override string toString() const
    {
        return "[href=" ~ href ~ "]";
    }
}

/// An endpoint operation's response: a body, a status and a content type.
final class WebEndpointResponse
{
    enum int STATUS_OK = 200; ///
    enum int STATUS_NO_CONTENT = 204; ///
    enum int STATUS_BAD_REQUEST = 400; ///
    enum int STATUS_NOT_FOUND = 404; ///
    enum int STATUS_TOO_MANY_REQUESTS = 429; ///
    enum int STATUS_INTERNAL_SERVER_ERROR = 500; ///
    enum int STATUS_SERVICE_UNAVAILABLE = 503; ///

    private Any body;
    private int status;
    private string contentType;

    /// `body` with `status` and `contentType` (or the negotiated type when `null`).
    this(Any body, int status = STATUS_OK, string contentType = null) pure nothrow @nogc
    {
        this.body = body;
        this.status = status;
        this.contentType = contentType;
    }

    /// The body; a null `Any` for none.
    Any getBody() pure nothrow @nogc
    {
        return
        body;
    }

    /// The HTTP status.
    int getStatus() const pure nothrow @nogc
    {
        return status;
    }

    /// The content type, or `null` to negotiate it.
    string getContentType() const pure nothrow @nogc
    {
        return contentType;
    }
}

/// The HTTP methods of endpoint operations.
enum WebEndpointHttpMethod
{
    GET, ///
    POST, ///
    DELETE ///
}

/// What an operation's request must look like: its path (relative to the endpoints' base path), method and media
/// types.
final class WebOperationRequestPredicate
{
    private string path;
    private WebEndpointHttpMethod httpMethod;
    private string[] consumes;
    private string[] produces;

    /// The predicate.
    this(string path, WebEndpointHttpMethod httpMethod, string[] consumes, string[] produces) pure nothrow
    {
        this.path = path;
        this.httpMethod = httpMethod;
        this.consumes = consumes;
        this.produces = produces;
    }

    /// The path, such as `health/{*path}`.
    string getPath() const pure nothrow @nogc
    {
        return path;
    }

    /// The HTTP method.
    WebEndpointHttpMethod getHttpMethod() const pure nothrow @nogc
    {
        return httpMethod;
    }

    /// The consumed media types.
    const(string)[] getConsumes() const pure nothrow @nogc
    {
        return consumes;
    }

    /// The produced media types.
    const(string)[] getProduces() const pure nothrow @nogc
    {
        return produces;
    }
}

/// An endpoint operation exposed over HTTP.
interface WebOperation
{
    /// The operation's id: the endpoint id, with `-` and the selector names when it has selectors.
    string getId();

    /// The request it answers.
    WebOperationRequestPredicate getRequestPredicate();

    /// Invoke the operation with its selector values (for an `ALL_REMAINING` selector, the remaining path
    /// segments).
    WebEndpointResponse invoke(string[] selectors);
}

/// An endpoint exposed over HTTP.
interface ExposableWebEndpoint
{
    /// The endpoint's id.
    EndpointId getEndpointId();

    /// The root path, relative to the base path.
    string getRootPath();

    /// The operations.
    WebOperation[] getOperations();
}

/// The base path the endpoints are mapped under.
final class EndpointMapping
{
    private string path;

    /// Under `path`, normalised to start and not end with `/` (empty for the root).
    this(string path) pure
    {
        this.path = normalizePath(path);
    }

    /// The base path.
    string getPath() const pure nothrow @nogc
    {
        return path;
    }

    /// `path` below the base path.
    string createSubPath(string path) const pure
    {
        return this.path ~ normalizePath(path);
    }

    private static string normalizePath(string path) pure
    {
        if (path.length == 0)
            return path;
        string normalized = path[0] == '/' ? path : "/" ~ path;
        if (normalized[$ - 1] == '/')
            normalized = normalized[0 .. $ - 1];
        return normalized;
    }
}

/// Resolves the links resource: `self`, then a link per operation of each endpoint.
class EndpointLinksResolver
{
    private ExposableWebEndpoint[] endpoints;

    /// Over `endpoints`.
    this(ExposableWebEndpoint[] endpoints) pure nothrow
    {
        this.endpoints = endpoints;
    }

    /// The links for a request to `requestUrl`.
    LinkedHashMap!(string, Link) resolveLinks(string requestUrl)
    {
        import std.algorithm.searching : endsWith, startsWith;

        const normalizedUrl = requestUrl.endsWith("/") ? requestUrl[0 .. $ - 1] : requestUrl;
        auto links = new LinkedHashMap!(string, Link);
        links.put("self", new Link(normalizedUrl));
        foreach (endpoint; endpoints)
        {
            foreach (operation; endpoint.getOperations())
            {
                const path = operation.getRequestPredicate().getPath();
                links.put(operation.getId(), new Link(normalizedUrl ~ (path.startsWith("/") ? path : "/" ~ path)));
            }
        }
        return links;
    }
}
