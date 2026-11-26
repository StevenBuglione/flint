/++
`org.springframework.web.servlet.resource`: static resources, and the 404 for a path nothing serves.

Ported from spring-projects/spring-framework v7.1.0,
spring-webmvc/src/main/java/org/springframework/web/servlet/resource/ (NoResourceFoundException.java,
ResourceHttpRequestHandler.java, ResourceHandlerUtils.java, ResourceResolver.java, ResourceResolverChain.java,
AbstractResourceResolver.java, PathResourceResolver.java) and .../mvc/HttpRequestHandlerAdapter.java,
.../handler/SimpleUrlHandlerMapping.java,
spring-web's HttpRequestHandler.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors. Explicitly configured classpath locations serve static resources.
Boot's unconfigured catch-all raises `NoResourceFoundException` for the error controller.
+/
module flint.web.servlet.resource;

import flint.core.io : ClassPathResource, FileSystemResource, Resource;
import flint.engine.aot.any : Any;
import flint.http : HttpHeaders, HttpMethod, HttpStatus, HttpStatusCode, MediaType, MediaTypeFactory, ProblemDetail;
import flint.http.converter : ResourceHttpMessageConverter;
import flint.http.server : ServletServerHttpResponse;
import flint.jakarta.servlet : ServletException;
import flint.jakarta.servlet.http : HttpServletRequest, HttpServletResponse;
import flint.java.io : IOException;
import flint.java.lang : IllegalArgumentException, IllegalStateException;
import flint.java.util : List;
import flint.util : StringUtils, toLowerAscii;
import flint.web : ErrorResponse, HttpRequestMethodNotSupportedException, skipBacktrace;
import flint.web.context.request : ServletWebRequest;
import flint.web.servlet : HandlerAdapter, HandlerMapping, ImmediateFailure, ModelAndView;
import flint.web.servlet.handler : AbstractHandlerMapping, lookupPath, parsedLookupPath;
import flint.web.util : UriUtils;
import flint.web.util.pattern : PathPattern, PathPatternParser;
import std.typecons : Nullable, nullable;

@safe:

/// `HttpRequestHandler`: a plain request handler.
interface HttpRequestHandler
{
    /// Handles the request.
    void handleRequest(HttpServletRequest request, HttpServletResponse response);
}

/// `NoResourceFoundException`: no static resource for the path (404).
class NoResourceFoundException : ServletException, ErrorResponse
{
    mixin ErrorResponse.Defaults;

    private HttpMethod httpMethod;
    private string resourcePath;
    private ProblemDetail body;

    ///
    this(HttpMethod httpMethod, string requestUri, string resourcePath)
    {
        super("No static resource " ~ resourcePath ~ " for request '" ~ requestUri ~ "'.");
        this.httpMethod = httpMethod;
        this.resourcePath = resourcePath;
        body = ProblemDetail.forStatusAndDetail(getStatusCode(), "No static resource " ~ resourcePath ~ ".");
        skipBacktrace(this);
    }

    /// The method.
    HttpMethod getHttpMethod() const pure nothrow @nogc
    {
        return httpMethod;
    }

    /// The resource path.
    string getResourcePath() const pure nothrow @nogc
    {
        return resourcePath;
    }

    HttpStatusCode getStatusCode()
    {
        return HttpStatus.NOT_FOUND;
    }

    ProblemDetail getBody()
    {
        return
        body;
    }
}

/// Validates request paths and location resources for the servlet resource chain.
abstract class ResourceHandlerUtils
{
    /// Checks that an inspectable location has a directory path and is safe to configure.
    static void assertResourceLocation(Resource location)
    {
        if (location is null)
            throw new IllegalArgumentException("Resource location must not be null");
        const path = locationPath(location);
        if (path is null)
            return;
        if (cast(ClassPathResource) location !is null && (path.length == 0 || path == "/"))
            throw new IllegalArgumentException("Resource location '" ~ location.getDescription()
                    ~ "' is considered unsafe and cannot be used as it provides access to the entire classpath.");
        if (path.length == 0 || (path[$ - 1] != '/' && path[$ - 1] != '\\'))
            throw new IllegalArgumentException("Resource location does not end with slash: " ~ path);
    }

    /// Appends the directory separator used by the location.
    static string initLocationPath(string path) pure nothrow
    {
        const separator = hasBytes(path, "/") ? '/' : '\\';
        return path.length != 0 && path[$ - 1] == separator ? path : path ~ separator;
    }

    /// Normalizes separators and drops leading control characters.
    static string normalizeInputPath(string path) pure nothrow
    {
        size_t start;
        bool slash;
        for (; start < path.length; start++)
        {
            const c = path[start];
            if (c == '/' || c == '\\')
                slash = true;
            else if (c > ' ' && c != 127)
                break;
        }
        const tail = path[start .. $];
        const normalized = collapseSeparators(tail);
        if (!slash)
            return normalized;
        if (start == 1 && path[0] == '/' && normalized is tail)
            return path;
        return "/" ~ normalized;
    }

    private static string collapseSeparators(string path) pure nothrow
    {
        char[] result;
        bool changed, slash;
        foreach (offset, c; path)
        {
            const normalized = c == '\\' ? '/' : c;
            const duplicate = slash && normalized == '/';
            if (!changed && (duplicate || c != normalized))
            {
                result = path[0 .. offset].dup;
                changed = true;
            }
            if (changed && !duplicate)
                result ~= normalized;
            slash = normalized == '/';
        }
        return changed ? result.idup : path;
    }

    /// Whether the normalized path or its percent-decoded form must be ignored.
    static bool shouldIgnoreInputPath(string path)
    {
        if (!StringUtils.hasText(path) || isInvalidPath(path))
            return true;
        if (!hasBytes(path, "%"))
            return false;
        try
        {
            auto decoded = UriUtils.decode(path);
            if (hasBytes(decoded, "%"))
                decoded = UriUtils.decode(decoded);
            if (!StringUtils.hasText(decoded) || isInvalidPath(decoded))
                return true;
            return isInvalidPath(normalizeInputPath(decoded));
        }
        catch (IllegalArgumentException)
        {
            return true;
        }
    }

    /// Rejects private container paths, URL selectors and parent-directory segments.
    static bool isInvalidPath(string path) pure nothrow
    {
        const lower = toLowerAscii(path);
        return hasBytes(lower, "web-inf") || hasBytes(lower, "meta-inf") || hasBytes(path, "../")
            || representsUrl(lower);
    }

    /// Whether both resources have the same class and the resource lies under the location path.
    static bool isResourceUnderLocation(Resource location, Resource resource)
    {
        if (location is null || resource is null || typeid(cast(Object) location) !is typeid(cast(Object) resource))
            return false;

        const basePath = locationPath(location);
        const resourcePath = locationPath(resource);
        if (resourcePath is null)
            return false;
        const cleanBase = StringUtils.cleanPath(basePath);
        if (cleanBase == resourcePath)
            return true;
        const prefix = cleanBase.length == 0 || cleanBase[$ - 1] == '/' ? cleanBase : cleanBase ~ "/";
        if (resourcePath.length < prefix.length || resourcePath[0 .. prefix.length] != prefix)
            return false;
        if (!hasBytes(resourcePath, "%"))
            return true;
        try
        {
            const decoded = UriUtils.decode(resourcePath);
            return !hasBytes(decoded, "../") && !hasBytes(decoded, "..\\");
        }
        catch (IllegalArgumentException)
        {
            // A readable resource can have a literal percent in its path.
            return true;
        }
    }

    private static string locationPath(Resource resource) pure nothrow @nogc
    {
        if (auto classPath = cast(ClassPathResource) resource)
        {
            const path = classPath.getPath();
            return path.length != 0 ? path : "";
        }
        if (auto fileSystem = cast(FileSystemResource) resource)
            return fileSystem.getPath();
        return null;
    }

    private static bool representsUrl(string path) pure nothrow @nogc
    {
        if (path.length != 0 && path[0] == '/')
            path = path[1 .. $];
        foreach (offset, c; path)
        {
            if (c == '/')
                return false;
            if (c != ':')
                continue;
            switch (path[0 .. offset])
            {
            case "classpath", "file", "jar", "http", "https", "ftp", "jrt", "mailto", "url":
                return true;
            default:
                return false;
            }
        }
        return false;
    }

    private static bool hasBytes(string text, string needle) pure nothrow @nogc
    {
        if (needle.length > text.length)
            return false;
        foreach (i; 0 .. text.length - needle.length + 1)
            if (text[i .. i + needle.length] == needle)
                return true;
        return false;
    }
}

/// Resolves an incoming resource path or the outbound path to a public resource.
interface ResourceResolver
{
    Resource resolveResource(HttpServletRequest request, string requestPath, List!Resource locations,
            ResourceResolverChain chain);

    Nullable!string resolveUrlPath(string resourcePath, List!Resource locations, ResourceResolverChain chain);
}

/// Delegates to the remaining resource resolvers.
interface ResourceResolverChain
{
    Resource resolveResource(HttpServletRequest request, string requestPath, List!Resource locations);

    Nullable!string resolveUrlPath(string resourcePath, List!Resource locations);
}

/// Template methods for a resource resolver.
abstract class AbstractResourceResolver : ResourceResolver
{
    Resource resolveResource(HttpServletRequest request, string requestPath, List!Resource locations,
            ResourceResolverChain chain)
    {
        return resolveResourceInternal(request, requestPath, locations, chain);
    }

    Nullable!string resolveUrlPath(string resourcePath, List!Resource locations, ResourceResolverChain chain)
    {
        return resolveUrlPathInternal(resourcePath, locations, chain);
    }

    protected abstract Resource resolveResourceInternal(HttpServletRequest request,
            string requestPath, List!Resource locations, ResourceResolverChain chain);

    protected abstract Nullable!string resolveUrlPathInternal(string resourcePath,
            List!Resource locations, ResourceResolverChain chain);
}

/// Resolves readable resources under the configured class-path and file-system locations.
class PathResourceResolver : AbstractResourceResolver
{
    private Resource[] allowedLocations;

    /// Also permits resources found under these locations.
    void setAllowedLocations(Resource[] locations...)
    {
        allowedLocations = locations.dup;
    }

    Resource[] getAllowedLocations()
    {
        return allowedLocations;
    }

    protected override Resource resolveResourceInternal(HttpServletRequest request,
            string requestPath, List!Resource locations, ResourceResolverChain chain)
    {
        return findResource(requestPath, locations);
    }

    protected override Nullable!string resolveUrlPathInternal(string resourcePath,
            List!Resource locations, ResourceResolverChain chain)
    {
        return StringUtils.hasText(resourcePath) && findResource(resourcePath, locations) !is null
            ? nullable(resourcePath) : Nullable!string.init;
    }

    private Resource findResource(string path, List!Resource locations)
    {
        if (locations is null)
            return null;
        foreach (location; locations)
        {
            try
            {
                if (auto resource = getResource(path, location))
                    return resource;
            }
            catch (IOException)
            {
                // Try the next location when this one cannot be read.
            }
        }
        return null;
    }

    /// Finds a readable resource relative to the location and checks its location boundary.
    protected Resource getResource(string resourcePath, Resource location)
    {
        if (location is null)
            return null;
        auto resource = location.createRelative(resourcePath);
        return resource !is null && checkResource(resource, location) && resource.isReadable() ? resource : null;
    }

    /// Checks the configured location and any additional allowed locations.
    protected bool checkResource(Resource resource, Resource location)
    {
        if (ResourceHandlerUtils.isResourceUnderLocation(location, resource))
            return true;
        foreach (allowed; allowedLocations)
            if (ResourceHandlerUtils.isResourceUnderLocation(allowed, resource))
                return true;
        return false;
    }
}

/// `ResourceHttpRequestHandler`: serves resources from configured classpath locations.
class ResourceHttpRequestHandler : HttpRequestHandler, ImmediateFailure
{
    private ResourceHandlerConfiguration configuration;
    private bool initialized;

    /// Sets the classpath locations before the handler is initialized or proved empty.
    final void setLocations(List!Resource sources)
    {
        if (sources is null)
            throw new IllegalArgumentException("Locations list must not be null");
        synchronized (this)
        {
            if (initialized)
                throw new IllegalStateException("Resource handler locations are frozen");
            configuration = sources.isEmpty() ? null : new ClassPathResourceHandlerConfiguration(sources);
        }
    }

    /// Validates the explicit locations and creates their resolver and message converter.
    void afterPropertiesSet()
    {
        synchronized (this)
        {
            if (initialized)
                return;
            if (configuration !is null)
                configuration.initialize();
            initialized = true;
        }
    }

    void handleRequest(HttpServletRequest request, HttpServletResponse response)
    {
        auto resource = getResource(request);
        if (resource is null)
            throw notFound(request);

        if (configuration is null)
            throw new IllegalStateException("Resource handler locations not initialized");
        configuration.handle(this, request, response, resource);
    }

    /// Resolves a valid mapped path under the configured locations.
    protected Resource getResource(HttpServletRequest request)
    {
        if (configuration is null)
            return null;
        auto pathWithin = request.getAttribute(HandlerMapping.PATH_WITHIN_HANDLER_MAPPING_ATTRIBUTE);
        if (pathWithin.isNull())
            throw new IllegalStateException(
                    "Required request attribute '"
                    ~ HandlerMapping.PATH_WITHIN_HANDLER_MAPPING_ATTRIBUTE ~ "' is not set");
        return configuration.resolve(this, request, pathWithin.get!string);
    }

    /// Normalizes the mapped resource path.
    protected string processPath(string path)
    {
        return ResourceHandlerUtils.normalizeInputPath(path);
    }

    /// Subclasses can reject more paths.
    protected bool isInvalidPath(string path)
    {
        return false;
    }

    /// Determines the resource media type from the servlet context or extension registry.
    protected Nullable!MediaType getMediaType(HttpServletRequest request, Resource resource)
    {
        return configuration is null ? Nullable!MediaType.init : configuration.getMediaType(request, resource);
    }

    private bool freezeEmpty()
    {
        synchronized (this)
        {
            if (configuration !is null)
                return false;
            initialized = true;
            return true;
        }
    }

    /// Flint: through Spring's `HttpRequestHandlerAdapter`, this handler's 404 is known before it runs, so the
    /// dispatcher takes it without a throw. A subclass or another adapter keeps the usual path.
    Exception immediateFailure(Object adapter, HttpServletRequest request)
    {
        if (typeid(this) !is typeid(ResourceHttpRequestHandler) || configuration !is null
                || adapter is null || typeid(adapter) !is typeid(HttpRequestHandlerAdapter))
            return null;
        return notFound(request);
    }

    private NoResourceFoundException notFound(HttpServletRequest request)
    {
        auto pathWithin = request.getAttribute(HandlerMapping.PATH_WITHIN_HANDLER_MAPPING_ATTRIBUTE);
        string path = pathWithin.isNull() ? lookupPath(request) : pathWithin.get!string;
        while (path.length != 0 && path[0] == '/')
            path = path[1 .. $];
        return new NoResourceFoundException(HttpMethod.valueOf(request.getMethod()), request.getRequestURI(), path);
    }
}

// Installed by explicit location configuration, keeping its implementation out of the stock handler.
private interface ResourceHandlerConfiguration
{
    void initialize();
    Resource resolve(ResourceHttpRequestHandler handler, HttpServletRequest request, string path);
    Nullable!MediaType getMediaType(HttpServletRequest request, Resource resource);
    void handle(ResourceHttpRequestHandler handler, HttpServletRequest request,
            HttpServletResponse response, Resource resource);
}

private final class ClassPathResourceHandlerConfiguration : ResourceHandlerConfiguration
{
    private List!Resource locations;
    private PathResourceResolver resolver;
    private ResourceHttpMessageConverter converter;

    this(List!Resource sources)
    {
        locations = List!Resource.copyOf(sources);
    }

    void initialize()
    {
        foreach (location; locations)
        {
            ResourceHandlerUtils.assertResourceLocation(location);
            if (typeid(cast(Object) location) !is typeid(ClassPathResource))
                throw new IllegalArgumentException("Expected a ClassPathResource location");
        }
        resolver = new PathResourceResolver();
        converter = new ResourceHttpMessageConverter();
    }

    Resource resolve(ResourceHttpRequestHandler handler, HttpServletRequest request, string rawPath)
    {
        auto path = handler.processPath(rawPath);
        if (ResourceHandlerUtils.shouldIgnoreInputPath(path) || handler.isInvalidPath(path))
            return null;
        if (resolver is null)
            throw new IllegalStateException("ResourceResolverChain not initialized");
        return resolver.resolveResource(request, path, locations, null);
    }

    Nullable!MediaType getMediaType(HttpServletRequest request, Resource resource)
    {
        Nullable!MediaType result;
        if (auto context = request.getServletContext())
        {
            const mimeType = context.getMimeType(resource.getFilename());
            if (StringUtils.hasText(mimeType))
                result = nullable(MediaType.parseMediaType(mimeType));
        }
        if (result.isNull || result.get() == MediaType.APPLICATION_OCTET_STREAM)
        {
            auto media = MediaTypeFactory.getMediaType(resource);
            if (media.isPresent())
                return nullable(media.get());
        }
        return result;
    }

    void handle(ResourceHttpRequestHandler handler, HttpServletRequest request,
            HttpServletResponse response, Resource resource)
    {
        const method = request.getMethod();
        if (method == "OPTIONS")
        {
            response.setHeader(HttpHeaders.ALLOW, "GET,HEAD,OPTIONS");
            return;
        }
        if (method != "GET" && method != "HEAD")
            throw new HttpRequestMethodNotSupportedException(method, ["GET", "HEAD"]);
        if (converter is null)
            throw new IllegalStateException("ResourceHttpMessageConverter not initialized");

        const lastModified = resource.isFile() ? resource.lastModified() : -1;
        if (new ServletWebRequest(request, response).checkNotModified(lastModified))
            return;

        auto contentType = handler.getMediaType(request, resource);
        const(MediaType)* media = contentType.isNull ? null : &contentType.get();
        auto message = new ServletServerHttpResponse(response);
        if (method == "HEAD")
        {
            converter.addDefaultHeaders(message, resource, media);
            message.flush();
        }
        else
            converter.write(Any.of(resource), media, message);
    }

}

/++
Flint's fast path (S6): whether `mapping` is exactly the stock resource mapping `WebMvcConfigurationSupport` builds:
a `SimpleUrlHandlerMapping` mapping only `/**`, to an exact `ResourceHttpRequestHandler` (which raises
`NoResourceFoundException` for every path), with no interceptors and no CORS configuration, so its chain for a `GET`
is the bare handler.
+/
package(flint.web) bool provedResourceFallback(HandlerMapping mapping)
{
    auto resources = cast(SimpleUrlHandlerMapping) mapping;
    if (resources is null || typeid(resources) !is typeid(SimpleUrlHandlerMapping)
            || resources.entries.length != 1 || resources.getAdaptedInterceptors().length != 0
            || resources.hasGlobalCorsConfiguration())
        return false;
    auto entry = resources.entries[0];
    return entry.pattern.getPatternString() == "/**" && entry.handler !is null
        && typeid(entry.handler) is typeid(ResourceHttpRequestHandler)
        && (cast(ResourceHttpRequestHandler) entry.handler).freezeEmpty();
}

/// `HttpRequestHandlerAdapter`.
class HttpRequestHandlerAdapter : HandlerAdapter
{
    bool supports(Object handler)
    {
        return cast(HttpRequestHandler) handler !is null;
    }

    ModelAndView handle(HttpServletRequest request, HttpServletResponse response, Object handler)
    {
        (cast(HttpRequestHandler) handler).handleRequest(request, response);
        return null;
    }
}

/// `SimpleUrlHandlerMapping`: URL patterns to handler objects (lowest precedence for `/**`).
class SimpleUrlHandlerMapping : AbstractHandlerMapping
{
    private static struct Entry
    {
        PathPattern pattern;
        Object handler;
    }

    private Entry[] entries;

    /// Maps `pattern` to `handler`.
    void registerHandler(string pattern, Object handler)
    {
        entries ~= Entry(new PathPatternParser().parse(pattern), handler);
    }

    protected override Object getHandlerInternal(HttpServletRequest request)
    {
        const path = lookupPath(request);
        const parsed = parsedLookupPath(request);
        foreach (entry; entries)
        {
            if (auto info = entry.pattern.matchAndExtract(parsed))
            {
                request.setAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE,
                        Any.of(entry.pattern.getPatternString()));
                request.setAttribute(HandlerMapping.PATH_WITHIN_HANDLER_MAPPING_ATTRIBUTE, Any.of(path));
                return entry.handler;
            }
        }
        return null;
    }
}
