/++
`org.springframework.test.web.servlet.request`: building MockMvc requests.

Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/main/java/org/springframework/test/web/servlet/request/ (MockMvcRequestBuilders.java,
MockHttpServletRequestBuilder.java, AbstractMockHttpServletRequestBuilder.java).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: `Object... uriVariables` is a template parameter pack (R7). The concrete
builder supplies the fluent URI and path methods (R12). Query parameters are decoded as UTF-8 (R14).
+/
module flint.test.web.servlet.request;

import flint.engine.aot.any : Any;
import flint.engine.aot.text : decimal;
import flint.http : HttpHeaders, HttpMethod, MediaType;
import flint.jakarta.servlet : ServletContext;
import flint.jakarta.servlet.http : Cookie;
import flint.java.lang : IllegalArgumentException, valueOf;
import flint.java.net : URI;
import flint.mock.web : MockHttpServletRequest;
import flint.test.web.servlet : RequestBuilder;
import flint.util : Assert, MultiValueMap, StringUtils;
import flint.web.util : UriComponentsBuilder, UriComponentType, UriUtils;
import std.typecons : Nullable;

@safe:

/// `MockHttpServletRequestBuilder`.
final class MockHttpServletRequestBuilder : RequestBuilder
{
    private struct Parameter
    {
        string name;
        string[] values;
    }

    private string method;
    private string rawPath;
    private string rawQuery;
    private string scheme;
    private string host;
    private int port = -1;
    private string uriTemplate;
    private string contextPathValue = "";
    private string servletPathValue = "";
    private Nullable!string pathInfoValue = Nullable!string("");
    private string[2][] headers;
    private Parameter[] parameters;
    private Parameter[] queryParameters;
    private const(ubyte)[] contentValue;
    private string contentTypeValue;
    private string characterEncodingValue;
    private Cookie[] cookies;
    private Any[string] attributes;
    private string[] attributeOrder;
    private bool secureValue;

    private this(string method)
    {
        if (method is null)
            throw new IllegalArgumentException("'httpMethod' is required");
        this.method = method;
    }

    /// Creates a builder using a method name and URI template.
    this(string method, string url)
    {
        this(method);
        uri(url);
    }

    /// Uses a fully formed URI and preserves its raw path and query.
    MockHttpServletRequestBuilder uri(URI target)
    {
        const text = target.toString();
        if (text is null)
            throw new IllegalArgumentException("'uri' is required");
        return updateUri(text, null);
    }

    /// Expands URI template variables in order and records the original template.
    MockHttpServletRequestBuilder uri(Args...)(string uriTemplate, Args uriVariables)
    {
        string[Args.length] values;
        static foreach (index; 0 .. Args.length)
            values[index] = valueOf(uriVariables[index]);
        return uriFromTemplate(uriTemplate, values[]);
    }

    private MockHttpServletRequestBuilder uriFromTemplate(string uriTemplate, scope const(string)[] variables)
    {
        if (uriTemplate is null)
            throw new IllegalArgumentException("'uri' must not be null");
        if (uriTemplate.length != 0 && !startsWith(uriTemplate, "/") && !startsWith(uriTemplate,
                "http://") && !startsWith(uriTemplate, "https://"))
            throw new IllegalArgumentException(
                    "'uri' should start with a path or be a complete HTTP URI: " ~ uriTemplate);
        const expanded = expand(uriTemplate.length == 0 ? "/" : uriTemplate, variables);
        return updateUri(expanded, uriTemplate);
    }

    private MockHttpServletRequestBuilder updateUri(string target, string templateValue)
    {
        auto end = indexOf(target, '#', 0);
        if (end >= 0)
            target = target[0 .. end];
        const delimiter = indexOf(target, '?', 0);
        const query = delimiter < 0 ? null : target[delimiter + 1 .. $];
        const authorityAndPath = delimiter < 0 ? target : target[0 .. delimiter];
        auto components = UriComponentsBuilder.fromUriString(authorityAndPath).build();
        const parsedPort = components.getPort();
        auto path = components.getPath();
        if (templateValue !is null && path.length == 0)
            path = "/";
        rawPath = templateValue is null ? path : encodePreservingEscapes(path, UriComponentType.PATH);
        rawQuery = templateValue is null ? query : encodePreservingEscapes(query, UriComponentType.QUERY);
        scheme = components.getScheme();
        host = components.getHost();
        port = parsedPort;
        this.uriTemplate = templateValue;
        return this;
    }

    private static bool startsWith(string value, string prefix) pure nothrow @nogc
    {
        return value.length >= prefix.length && value[0 .. prefix.length] == prefix;
    }

    private static ptrdiff_t indexOf(string text, char c, size_t from) pure nothrow @nogc
    {
        foreach (i; from .. text.length)
            if (text[i] == c)
                return i;
        return -1;
    }

    /// Adds a request parameter.
    MockHttpServletRequestBuilder param(string name, string[] values...)
    {
        parameters ~= Parameter(name, values.dup);
        return this;
    }

    /// Adds each entry of a parameter map in iteration order.
    MockHttpServletRequestBuilder params(MultiValueMap!(string, string) values)
    {
        Assert.notNull(values, "'params' must not be null");
        values.forEach((name, entries) { param(name, entries.toArray()); });
        return this;
    }

    /// Adds a query parameter (also appended to the query string).
    MockHttpServletRequestBuilder queryParam(string name, string[] values...)
    {
        queryParameters ~= Parameter(name, values.dup);
        return this;
    }

    /// Adds each entry of a map to the query string and request parameters.
    MockHttpServletRequestBuilder queryParams(MultiValueMap!(string, string) values)
    {
        Assert.notNull(values, "'params' must not be null");
        values.forEach((name, entries) { queryParam(name, entries.toArray()); });
        return this;
    }

    /// Adds a header.
    MockHttpServletRequestBuilder header(string name, string[] values...)
    {
        foreach (value; values)
            headers ~= [name, value];
        return this;
    }

    /// Sets `Accept`.
    MockHttpServletRequestBuilder accept(MediaType[] mediaTypes...)
    {
        return header(HttpHeaders.ACCEPT, MediaType.toString(mediaTypes));
    }

    /// Sets `Accept` from text.
    MockHttpServletRequestBuilder accept(string[] mediaTypes...)
    {
        string joined;
        foreach (i, m; mediaTypes)
            joined ~= (i == 0 ? "" : ", ") ~ m;
        return header(HttpHeaders.ACCEPT, joined);
    }

    /// Sets the content type.
    MockHttpServletRequestBuilder contentType(MediaType contentType)
    {
        contentTypeValue = contentType.toString();
        return this;
    }

    /// ditto
    MockHttpServletRequestBuilder contentType(string contentType)
    {
        contentTypeValue = contentType;
        return this;
    }

    /// Sets the body.
    MockHttpServletRequestBuilder content(string content)
    {
        contentValue = cast(const(ubyte)[]) content;
        return this;
    }

    /// ditto
    MockHttpServletRequestBuilder content(const(ubyte)[] content)
    {
        contentValue = content;
        return this;
    }

    /// Sets the character encoding.
    MockHttpServletRequestBuilder characterEncoding(string encoding)
    {
        characterEncodingValue = encoding;
        return this;
    }

    /// Adds cookies.
    MockHttpServletRequestBuilder cookie(Cookie[] cookies...)
    {
        this.cookies ~= cookies;
        return this;
    }

    /// Sets a request attribute.
    MockHttpServletRequestBuilder requestAttr(string name, Any value)
    {
        if (name !in attributes)
            attributeOrder ~= name;
        attributes[name] = value;
        return this;
    }

    /// Sets the context path.
    MockHttpServletRequestBuilder contextPath(string contextPath)
    {
        validatePathPrefix(contextPath, "Context path");
        contextPathValue = contextPath;
        return this;
    }

    /// Sets the servlet path.
    MockHttpServletRequestBuilder servletPath(string servletPath)
    {
        validatePathPrefix(servletPath, "Servlet path");
        servletPathValue = servletPath;
        return this;
    }

    private static void validatePathPrefix(string path, string description)
    {
        if (!StringUtils.hasText(path))
            return;
        if (path[0] != '/')
            throw new IllegalArgumentException(description ~ " must start with a '/'");
        if (path[$ - 1] == '/')
            throw new IllegalArgumentException(description ~ " must not end with a '/'");
    }

    /// Sets the path info explicitly. An empty value derives it from the request URI.
    MockHttpServletRequestBuilder pathInfo(string pathInfo)
    {
        return this.pathInfo(pathInfo is null ? Nullable!string.init : Nullable!string(pathInfo));
    }

    /// Accepts the nullable servlet path-info value (R5).
    MockHttpServletRequestBuilder pathInfo(Nullable!string pathInfo)
    {
        if (!pathInfo.isNull && StringUtils.hasText(pathInfo.get()) && pathInfo.get()[0] != '/')
            throw new IllegalArgumentException("Path info must start with a '/'");
        pathInfoValue = pathInfo;
        return this;
    }

    /// Marks the request secure (`https`).
    MockHttpServletRequestBuilder secure(bool secure)
    {
        secureValue = secure;
        return this;
    }

    MockHttpServletRequest buildRequest(ServletContext servletContext)
    {
        auto request = new MockHttpServletRequest(method, rawPath);
        if (scheme !is null)
            request.setScheme(scheme);
        else if (secureValue)
        {
            request.setScheme("https");
            request.setServerPort(443);
        }
        if (host !is null)
            request.setServerName(host);
        if (port >= 0)
            request.setServerPort(port);
        updatePath(request);

        string query = rawQuery;
        foreach (pair; parseQuery(rawQuery))
            request.addParameter(pair[0], pair[1]);
        foreach (parameter; queryParameters)
        {
            if (parameter.values.length == 0)
                query = appendQuery(query, parameter.name, null);
            else
                foreach (value; parameter.values)
                    query = appendQuery(query, parameter.name, value);
            request.addParameter(parameter.name, parameter.values);
        }
        request.setQueryString(query);
        foreach (parameter; parameters)
            request.addParameter(parameter.name, parameter.values);
        foreach (pair; headers)
            request.addHeader(pair[0], pair[1]);
        if (contentTypeValue !is null)
            request.setContentType(contentTypeValue);
        if (characterEncodingValue !is null)
            request.setCharacterEncoding(characterEncodingValue);
        if (contentValue !is null)
        {
            request.setContent(contentValue);
            if (request.getHeader(HttpHeaders.CONTENT_LENGTH) is null)
                request.addHeader(HttpHeaders.CONTENT_LENGTH, decimal(contentValue.length));
        }
        if (cookies.length != 0)
            request.setCookies(cookies);
        foreach (name; attributeOrder)
            request.setAttribute(name, attributes[name]);
        return request;
    }

    private void updatePath(MockHttpServletRequest request)
    {
        if (!startsWith(rawPath, contextPathValue))
            throw new IllegalArgumentException(
                    "Request URI [" ~ rawPath ~ "] does not start with context path [" ~ contextPathValue ~ "]");
        request.setContextPath(contextPathValue);
        request.setServletPath(servletPathValue);
        auto pathInfo = pathInfoValue;
        if (!pathInfo.isNull && pathInfo.get().length == 0)
        {
            const remaining = rawPath[contextPathValue.length .. $];
            if (!startsWith(remaining, servletPathValue))
                throw new IllegalArgumentException(
                        "Invalid servlet path [" ~ servletPathValue ~ "] for request URI [" ~ rawPath ~ "]");
            const tail = remaining[servletPathValue.length .. $];
            pathInfo = StringUtils.hasText(tail) ? Nullable!string(UriUtils.decode(tail)) : Nullable!string.init;
        }
        request.setPathInfo(pathInfo);
        request.setUriTemplate(uriTemplate is null ? Nullable!string.init : Nullable!string(uriTemplate));
    }

    private static string appendQuery(string query, string name, string value)
    {
        const pair = UriUtils.encodeQueryParam(name) ~ (value is null ? "" : "=" ~ UriUtils.encodeQueryParam(value));
        return query.length == 0 ? pair : query ~ "&" ~ pair;
    }

    private static string[2][] parseQuery(string query)
    {
        string[2][] result;
        if (query.length == 0)
            return result;
        size_t start;
        foreach (i; 0 .. query.length + 1)
        {
            if (i == query.length || query[i] == '&')
            {
                auto pair = query[start .. i];
                start = i + 1;
                if (pair.length == 0)
                    continue;
                ptrdiff_t eq = indexOf(pair, '=', 0);
                if (eq < 0)
                {
                    result ~= [UriUtils.decode(pair), null];
                    continue;
                }
                result ~= [UriUtils.decode(pair[0 .. eq]), UriUtils.decode(pair[eq + 1 .. $])];
            }
        }
        return result;
    }

    private static string encodePreservingEscapes(string text, UriComponentType component)
    {
        string result;
        size_t start;
        for (size_t index; index + 2 < text.length; ++index)
        {
            if (text[index] != '%' || !isHex(text[index + 1]) || !isHex(text[index + 2]))
                continue;
            result ~= UriUtils.encodeUriComponent(text[start .. index], component) ~ text[index .. index + 3];
            index += 2;
            start = index + 1;
        }
        return start == 0 ? UriUtils.encodeUriComponent(text,
                component) : result ~ UriUtils.encodeUriComponent(text[start .. $], component);
    }

    private static bool isHex(char c) pure nothrow @nogc
    {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }

    private static string expand(string template_, scope const(string)[] values)
    {
        if (indexOf(template_, '{', 0) < 0)
            return template_;
        string result;
        size_t next;
        bool inQuery;
        for (size_t index; index < template_.length; ++index)
        {
            const character = template_[index];
            if (character == '#')
                break;
            if (character == '?')
                inQuery = true;
            if (character != '{')
            {
                result ~= character;
                continue;
            }
            const close = indexOf(template_, '}', index + 1);
            if (close < 0)
                throw new IllegalArgumentException("Invalid URI template: " ~ template_);
            if (next == values.length)
                throw new IllegalArgumentException(
                        "Not enough variable values available to expand '" ~ template_[index + 1 .. close] ~ "'");
            const value = values[next++];
            result ~= inQuery ? UriUtils.encodeQueryParam(value) : UriUtils.encodePathSegment(value);
            index = close;
        }
        return result;
    }
}

/// `MockMvcRequestBuilders`: static factory methods for requests.
struct MockMvcRequestBuilders
{
    /// GET `uriTemplate`, with `{}` variables expanded in order.
    static MockHttpServletRequestBuilder get(Args...)(string uriTemplate, Args uriVariables)
    {
        return request!Args("GET", uriTemplate, uriVariables);
    }

    /// GET with a URI.
    static MockHttpServletRequestBuilder get(URI uri)
    {
        return request(HttpMethod.GET, uri);
    }

    /// POST.
    static MockHttpServletRequestBuilder post(Args...)(string uriTemplate, Args uriVariables)
    {
        return request!Args("POST", uriTemplate, uriVariables);
    }

    /// POST with a URI.
    static MockHttpServletRequestBuilder post(URI uri)
    {
        return request(HttpMethod.POST, uri);
    }

    /// PUT.
    static MockHttpServletRequestBuilder put(Args...)(string uriTemplate, Args uriVariables)
    {
        return request!Args("PUT", uriTemplate, uriVariables);
    }

    /// PUT with a URI.
    static MockHttpServletRequestBuilder put(URI uri)
    {
        return request(HttpMethod.PUT, uri);
    }

    /// PATCH.
    static MockHttpServletRequestBuilder patch(Args...)(string uriTemplate, Args uriVariables)
    {
        return request!Args("PATCH", uriTemplate, uriVariables);
    }

    /// PATCH with a URI.
    static MockHttpServletRequestBuilder patch(URI uri)
    {
        return request(HttpMethod.PATCH, uri);
    }

    /// DELETE.
    static MockHttpServletRequestBuilder delete_(Args...)(string uriTemplate, Args uriVariables)
    {
        return request!Args("DELETE", uriTemplate, uriVariables);
    }

    /// DELETE with a URI.
    static MockHttpServletRequestBuilder delete_(URI uri)
    {
        return request(HttpMethod.DELETE, uri);
    }

    /// OPTIONS.
    static MockHttpServletRequestBuilder options(Args...)(string uriTemplate, Args uriVariables)
    {
        return request!Args("OPTIONS", uriTemplate, uriVariables);
    }

    /// OPTIONS with a URI.
    static MockHttpServletRequestBuilder options(URI uri)
    {
        return request(HttpMethod.OPTIONS, uri);
    }

    /// HEAD.
    static MockHttpServletRequestBuilder head(Args...)(string uriTemplate, Args uriVariables)
    {
        return request!Args("HEAD", uriTemplate, uriVariables);
    }

    /// HEAD with a URI.
    static MockHttpServletRequestBuilder head(URI uri)
    {
        return request(HttpMethod.HEAD, uri);
    }

    /// Any method.
    static MockHttpServletRequestBuilder request(Args...)(HttpMethod method, string uriTemplate, Args uriVariables)
    {
        return request!Args(method.name(), uriTemplate, uriVariables);
    }

    /// ditto, by name.
    static MockHttpServletRequestBuilder request(Args...)(string method, string uriTemplate, Args uriVariables)
    {
        return (new MockHttpServletRequestBuilder(method)).uri(uriTemplate, uriVariables);
    }

    /// Any method, with a URI.
    static MockHttpServletRequestBuilder request(HttpMethod method, URI uri)
    {
        return (new MockHttpServletRequestBuilder(method.name())).uri(uri);
    }

    /// Any method by name, with a URI.
    deprecated("use request(HttpMethod, URI)") static MockHttpServletRequestBuilder request(string method, URI uri)
    {
        return request(HttpMethod.valueOf(method), uri);
    }
}
