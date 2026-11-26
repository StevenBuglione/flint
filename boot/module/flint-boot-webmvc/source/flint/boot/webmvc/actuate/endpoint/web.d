// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/main/java/org/springframework/boot/webmvc/actuate/endpoint/web/WebMvcEndpointHandlerMapping.java
// with AbstractWebMvcEndpointHandlerMapping.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Spring MVC's handler methods for the endpoints are Flint AOT request-mapping rows,
// built from two handler classes and added to the DispatcherServlet's request mappings (Flint's RequestMappingInfo
// table is Flint AOT's), at the base path; an `ALL_REMAINING` selector reads the rest of the request path.

/// `org.springframework.boot.webmvc.actuate.endpoint.web`: actuator endpoints in Spring MVC.
module flint.boot.webmvc.actuate.endpoint.web;

import flint.boot.actuate.endpoint : ApiVersion, getProducedMimeType;
import flint.boot.actuate.endpoint.web : EndpointLinksResolver, EndpointMapping,
    ExposableWebEndpoint, Link, WebOperation;
import flint.engine.aot.any : Any;
import flint.engine.aot.mapping : HandlerMapping;
import flint.http : HttpStatusCode, ResponseEntity;
import flint.jakarta.servlet.http : HttpServletRequest;
import flint.java.util : LinkedHashMap;
import flint.web.bind.annotation : RequestMapping, ResponseBody;

// The handler methods' mapping: paths, methods and media types are set per endpoint at runtime.
private enum RequestMapping endpointMapping = RequestMapping.init;

@safe:

/// Maps the exposed web endpoints, and the links resource at the base path, onto Spring MVC.
class WebMvcEndpointHandlerMapping
{
    private EndpointMapping endpointMapping;
    private ExposableWebEndpoint[] endpoints;
    private bool linksEnabled;

    /// `endpoints` under `endpointMapping`, with the links resource when `linksEnabled`.
    this(EndpointMapping endpointMapping, ExposableWebEndpoint[] endpoints, bool linksEnabled)
    {
        this.endpointMapping = endpointMapping;
        this.endpoints = endpoints;
        this.linksEnabled = linksEnabled;
    }

    /// The base path.
    EndpointMapping getEndpointMapping() pure nothrow @nogc
    {
        return endpointMapping;
    }

    /// The exposed endpoints.
    ExposableWebEndpoint[] getEndpoints() pure nothrow @nogc
    {
        return endpoints;
    }

    /// The handlers to register as singletons, by bean name, and their request-mapping rows.
    void contribute(void delegate(string name, Object handler) @safe register, ref HandlerMapping[] rows)
    {
        import flint.web.servlet.mvc.method.aot : requestMappingsOf;

        const produces = [
            getProducedMimeType(ApiVersion.V3), getProducedMimeType(ApiVersion.V2), "application/json"
        ];
        if (linksEnabled && endpointMapping.getPath().length)
        {
            enum name = "flint.boot.webmvc.actuate.endpoint.web.links";
            register(name, new LinksHandler(new EndpointLinksResolver(endpoints)));
            foreach (row; requestMappingsOf!LinksHandler(name))
            {
                row.paths = [endpointMapping.getPath(), endpointMapping.getPath() ~ "/"];
                row.produces = produces.dup;
                rows ~= row;
            }
        }
        foreach (endpoint; endpoints)
        {
            foreach (operation; endpoint.getOperations())
            {
                const name = "flint.boot.webmvc.actuate.endpoint.web." ~ operation.getId();
                const path = endpointMapping.createSubPath(operation.getRequestPredicate().getPath());
                register(name, new OperationHandler(operation, path));
                foreach (row; requestMappingsOf!OperationHandler(name))
                {
                    row.paths = [path];
                    row.methods = [methodName(operation)];
                    row.produces = operation.getRequestPredicate().getProduces().dup;
                    rows ~= row;
                }
            }
        }
    }

    private static string methodName(WebOperation operation)
    {
        import flint.engine.aot.text : enumName;

        return enumName(operation.getRequestPredicate().getHttpMethod());
    }
}

/// The links resource's body: `{"_links": {...}}`.
alias Links = LinkedHashMap!(string, LinkedHashMap!(string, Link));

/// The links resource: `{"_links": {...}}` for the request's URL.
final class LinksHandler
{
    private EndpointLinksResolver resolver;

    /// Over `resolver`.
    this(EndpointLinksResolver resolver) pure nothrow @nogc
    {
        this.resolver = resolver;
    }

    /// The links.
    @endpointMapping
    @ResponseBody
    Links links(HttpServletRequest request)
    {
        auto body = new Links;
        body.put("_links", resolver.resolveLinks(request.getRequestURL()));
        return
        body;
    }
}

/// One operation: its selectors from the request path, its response as a `ResponseEntity`.
final class OperationHandler
{
    private WebOperation operation;
    private string path;

    /// `operation`, mapped at `path`.
    this(WebOperation operation, string path) pure nothrow @nogc
    {
        this.operation = operation;
        this.path = path;
    }

    /// Invoke the operation.
    @endpointMapping
    ResponseEntity handle(HttpServletRequest request)
    {
        auto response = operation.invoke(selectors(request));
        auto status = HttpStatusCode.valueOf(response.getStatus());
        if (response.getBody().isNull())
            return ResponseEntity(status);
        return ResponseEntity.of(response.getBody(), status);
    }

    // The path segments an ALL_REMAINING selector (`{*path}`) matches.
    private string[] selectors(HttpServletRequest request)
    {
        // Flint: plain loops, not std.algorithm/std.array/std.string, whose ModuleInfo and instances pull
        // std.socket and the rest of Phobos's network objects into every app (playbook S-9).
        const capture = indexOfCapture(path);
        if (capture == size_t.max)
            return null;
        const prefix = request.getContextPath() ~ path[0 .. capture + 1];
        const uri = request.getRequestURI();
        if (uri.length <= prefix.length)
            return null;
        return segmentsOf(uri[prefix.length .. $]);
    }
}

// The index of the first "/{*" in `text`, or size_t.max.
private size_t indexOfCapture(scope const(char)[] text) pure nothrow @nogc
{
    foreach (i; 0 .. text.length)
        if (i + 2 < text.length && text[i] == '/' && text[i + 1] == '{' && text[i + 2] == '*')
            return i;
    return size_t.max;
}

// The non-empty '/'-separated segments of `text`.
private string[] segmentsOf(string text) pure nothrow
{
    string[] segments;
    size_t start;
    foreach (i; 0 .. text.length + 1)
    {
        if (i < text.length && text[i] != '/')
            continue;
        if (i > start)
            segments ~= text[start .. i];
        start = i + 1;
    }
    return segments;
}
