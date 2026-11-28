/++
`org.springframework.web.util.ServletRequestPathUtils`: the request's application-relative path, parsed once per
request and cached under `pathAttribute`.

Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/main/java/org/springframework/web/util/ServletRequestPathUtils.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: Spring's `RequestPath` is the existing `PathContainer` (the same parse the handler
mappings match), and the parsed path and its segments live in one object per request.
+/
module flint.web.util.request_path;

import flint.engine.aot.any : Any;
import flint.jakarta.servlet.http : HttpServletRequest;
import flint.java.lang : IllegalArgumentException;
import flint.web.util.pattern : PathContainer;

@safe:

/// The application-relative, still-encoded request path (Spring 6's parsed `RequestPath.pathWithinApplication()`).
string lookupPath(HttpServletRequest request)
{
    const uri = request.getRequestURI();
    const contextPath = request.getContextPath();
    if (contextPath.length != 0 && uri.length >= contextPath.length && uri[0 .. contextPath.length] == contextPath)
        return uri[contextPath.length .. $];
    return uri;
}

/// The request attribute holding the parsed lookup path (Spring's `ServletRequestPathUtils.PATH_ATTRIBUTE`).
package(flint) enum string pathAttribute = "org.springframework.web.util.ServletRequestPathUtils.PATH";

/++
The lookup path parsed into segments, once per request (Spring's `ServletRequestPathUtils.parseAndCache`): every
pattern of every mapping matches the same parse. The parse is kept under `pathAttribute` and reused while the
request's lookup path is unchanged, so a forward or include, which changes it, parses its own.
+/
package(flint) PathContainer parsedLookupPath(HttpServletRequest request)
{
    const path = lookupPath(request);
    if (auto holder = cast(ParsedPath) request.getAttribute(pathAttribute).asObject())
    {
        if (holder.parsed.raw is path || holder.parsed.raw == path)
            return holder.parsed;
    }
    // One allocation per request: the parse and up to four segments live in one object, stored by reference.
    auto holder = new ParsedPath;
    holder.parsed = PathContainer.parsePath(path, holder.segments[]);
    request.setAttribute(pathAttribute, Any.of(holder));
    return holder.parsed;
}

/// The cached lookup path, or an `IllegalArgumentException` when nothing parsed it (`getCachedPathValue`).
package(flint) string cachedLookupPath(HttpServletRequest request)
{
    if (auto holder = cast(ParsedPath) request.getAttribute(pathAttribute).asObject())
        return holder.parsed.raw;
    throw new IllegalArgumentException("RequestPath not parsed");
}

/// A request's parsed lookup path, with room for its segments.
private final class ParsedPath
{
    PathContainer parsed;
    string[4] segments;
}
