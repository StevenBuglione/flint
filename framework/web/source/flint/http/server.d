/++
`org.springframework.http.server`: the server-side `HttpRequest` and response, over the servlet API.

Ported from spring-projects/spring-framework v7.1.0, spring-web/src/main/java/org/springframework/http/server/
(ServerHttpRequest.java, ServerHttpResponse.java, ServletRequestHeadersAdapter.java,
ServletResponseHeadersAdapter.java, ServletServerHttpRequest.java, ServletServerHttpResponse.java).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: translated to D under the rulebook (docs/spring/api-mapping.md). As in Spring 7,
flushing the body stream is a no-op and `flush()` commits the servlet response only once a body was written,
which is why `@ResponseBody` responses carry `Content-Length` while `ResponseEntity` bodies are chunked.
+/
module flint.http.server;

import flint.http : HttpHeaders, HttpInputMessage, HttpMethod, HttpOutputMessage, HttpRequest,
    HttpStatusCode, MediaType;
import flint.jakarta.servlet.http : HeaderFieldSource, HttpServletRequest, HttpServletResponse;
import flint.java.lang : IllegalArgumentException;
import flint.java.net : URI;
import flint.java.nio.charset : Charset, StandardCharsets;

@safe:

/// `ServerHttpRequest`.
interface ServerHttpRequest : HttpRequest, HttpInputMessage
{
}

/// `ServerHttpResponse`.
interface ServerHttpResponse : HttpOutputMessage
{
    /// Sets the status.
    void setStatusCode(HttpStatusCode status);

    /// Writes headers, and commits the response when a body was written.
    void flush();

    /// Writes headers.
    void close();
}

/// `ServletServerHttpRequest`.
class ServletServerHttpRequest : ServerHttpRequest
{
    private HttpServletRequest servletRequest;
    private HttpHeaders headers;
    private bool headersRead;

    ///
    this(HttpServletRequest servletRequest) pure nothrow @nogc
    {
        this.servletRequest = servletRequest;
    }

    /// The wrapped request.
    HttpServletRequest getServletRequest() pure nothrow @nogc
    {
        return servletRequest;
    }

    HttpMethod getMethod()
    {
        return HttpMethod.valueOf(servletRequest.getMethod());
    }

    URI getURI()
    {
        const query = servletRequest.getQueryString();
        return URI.create(servletRequest.getRequestURL() ~ (query !is null ? "?" ~ query : ""));
    }

    HttpHeaders getHeaders()
    {
        if (!headersRead)
        {
            headers = HttpHeaders.create();
            // A container request hands its fields over in one pass; HttpHeaders groups each name's values
            // case-insensitively in arrival order, as reading them name by name does.
            if (auto fields = cast(HeaderFieldSource) servletRequest)
                fields.visitHeaderFields((string name, string value) { headers.add(name, value); });
            else
                foreach (name; servletRequest.getHeaderNames())
                    foreach (value; servletRequest.getHeaders(name))
                        headers.add(name, value);
            reconcileContentType();
            const length = servletRequest.getContentLengthLong();
            if (length >= 0 && !headers.containsHeader(HttpHeaders.CONTENT_LENGTH))
                headers.setContentLength(length);
            headersRead = true;
        }
        return headers;
    }

    private void reconcileContentType()
    {
        auto text = headers.getFirst(HttpHeaders.CONTENT_TYPE);
        if (text.length == 0)
            return;
        const encoding = servletRequest.getCharacterEncoding();
        if (encoding.length == 0 || hasCharsetSuffix(text, encoding))
            return;

        try
        {
            auto mediaType = MediaType.parseMediaType(text);
            if (!mediaType.getCharset())
            {
                mediaType = MediaType(mediaType, Charset.forName(encoding));
                text = mediaType.toString();
                headers.set(HttpHeaders.CONTENT_TYPE, text);
            }
            headers.rememberContentType(text, mediaType);
        }
        catch (IllegalArgumentException)
        {
            // Keep the original header when the media type or servlet encoding cannot be parsed.
        }
    }

    const(ubyte)[] getBody()
    {
        const type = servletRequest.getContentType();
        if (isFormPost(type) && servletRequest.getQueryString() is null && !hasUnhandledFormCharset(type))
        {
            auto requestHeaders = getHeaders();
            if (usesUtf8(requestHeaders))
                return reconstructFormBody(requestHeaders);
        }
        return servletRequest.getInputStream().readAllBytes();
    }

    private bool isFormPost(string type)
    {
        enum formType = MediaType.APPLICATION_FORM_URLENCODED_VALUE;
        if (type.length < formType.length)
            return false;
        foreach (start; 0 .. type.length - formType.length + 1)
            if (type[start .. start + formType.length] == formType)
                return servletRequest.getMethod() == "POST";
        return false;
    }

    private bool hasUnhandledFormCharset(string type)
    {
        if (headersRead)
            return false;
        const encoding = servletRequest.getCharacterEncoding();
        if (encoding.length == 0 || !hasCharsetSuffix(type, encoding))
            return false;
        return !Charset.isSupported(encoding) || Charset.forName(encoding) != StandardCharsets.UTF_8;
    }

    pragma(inline, false) private const(ubyte)[] reconstructFormBody(HttpHeaders requestHeaders)
    {
        char[] encoded;
        auto names = servletRequest.getParameterNames();
        foreach (nameIndex, name; names)
        {
            auto values = servletRequest.getParameterValues(name);
            foreach (valueIndex, value; values)
            {
                appendFormComponent(encoded, name);
                if (value !is null)
                {
                    encoded ~= '=';
                    appendFormComponent(encoded, value);
                    if (valueIndex + 1 < values.length)
                        encoded ~= '&';
                }
            }
            if (nameIndex + 1 < names.length)
                encoded ~= '&';
        }
        if (encoded.length != 0 && requestHeaders.containsHeader(HttpHeaders.CONTENT_LENGTH))
            requestHeaders.setContentLength(cast(long) encoded.length);
        return cast(const(ubyte)[]) encoded;
    }
}

/// Form reconstruction currently encodes UTF-8. Unhandled encodings use the servlet's bytes.
private bool usesUtf8(HttpHeaders headers) pure
{
    try
    {
        MediaType type;
        if (!headers.readContentType(type))
            return true;
        const charset = type.getCharset();
        return charset is null || *charset == StandardCharsets.UTF_8;
    }
    catch (IllegalArgumentException)
    {
        return false;
    }
}

/// Java URLEncoder rules for one UTF-8 form name or value.
pragma(inline, false) private void appendFormComponent(ref char[] output, string value) pure nothrow
{
    static immutable hex = "0123456789ABCDEF";
    foreach (char c; value)
    {
        if (c == ' ')
            output ~= '+';
        else if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-'
                || c == '_' || c == '.' || c == '*')
            output ~= c;
        else
        {
            char[3] escaped = ['%', hex[c >> 4], hex[c & 15]];
            output ~= escaped[];
        }
    }
}

/// `ServletServerHttpResponse`.
class ServletServerHttpResponse : ServerHttpResponse
{
    private HttpServletResponse servletResponse;
    private HttpHeaders headers;
    private bool headersWritten;
    private bool bodyUsed;

    ///
    this(HttpServletResponse servletResponse) pure nothrow
    {
        this.servletResponse = servletResponse;
        headers = HttpHeaders.create();
    }

    /// The wrapped response.
    HttpServletResponse getServletResponse() pure nothrow @nogc
    {
        return servletResponse;
    }

    void setStatusCode(HttpStatusCode status)
    {
        servletResponse.setStatus(status.value());
    }

    /// The headers; read-only once written.
    HttpHeaders getHeaders() pure nothrow
    {
        return headersWritten ? HttpHeaders.readOnlyHttpHeaders(headers) : headers;
    }

    void writeBody(scope const(ubyte)[] bytes)
    {
        bodyUsed = true;
        writeHeaders();
        servletResponse.getOutputStream().write(bytes);
    }

    void flush()
    {
        writeHeaders();
        if (bodyUsed)
            servletResponse.flushBuffer();
    }

    void close()
    {
        writeHeaders();
    }

    private void writeHeaders()
    {
        if (headersWritten)
            return;
        foreach (name, values; headers)
        {
            if (equalsAscii(name, HttpHeaders.CONTENT_TYPE))
                servletResponse.setHeader(HttpHeaders.CONTENT_TYPE, values.length != 0 ? values[0] : null);
            else if (equalsAscii(name, HttpHeaders.CONTENT_LENGTH))
            {
                import flint.http : parseJavaLong;

                if (values.length != 0)
                    servletResponse.setContentLengthLong(parseJavaLong(values[0]));
            }
            else
                foreach (value; values)
                    servletResponse.addHeader(name, value);
        }
        headersWritten = true;
    }
}

/// An unquoted final charset already matches the servlet's encoding.
private bool hasCharsetSuffix(string text, string encoding) pure nothrow @nogc
{
    enum parameter = "charset=";
    if (text.length <= encoding.length + parameter.length)
        return false;
    const value = text.length - encoding.length;
    auto name = value - parameter.length;
    if (text[value .. $] != encoding || !equalsAscii(text[name .. value], parameter))
        return false;
    while (name > 0 && (text[name - 1] == ' ' || text[name - 1] == '\t'))
        --name;
    if (name == 0 || text[name - 1] != ';')
        return false;
    foreach (c; text[0 .. name - 1])
        if (c == '"' || c == '\'')
            return false;
    return true;
}

private bool equalsAscii(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
{
    if (a.length != b.length)
        return false;
    foreach (i, c; a)
    {
        const x = c >= 'A' && c <= 'Z' ? cast(char)(c + 32) : c;
        const y = b[i] >= 'A' && b[i] <= 'Z' ? cast(char)(b[i] + 32) : b[i];
        if (x != y)
            return false;
    }
    return true;
}
