/++
`org.springframework.mock.web`: servlet API mocks for tests.

Ported from spring-projects/spring-framework v7.1.0, spring-test/src/main/java/org/springframework/mock/web/
(MockHttpServletRequest.java, MockHttpServletResponse.java, MockServletContext.java, DelegatingServletInputStream,
DelegatingServletOutputStream).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: translated to D under the rulebook. Header and parameter maps keep Spring's
insertion order and case rules. `sendError` records the status and message and commits the response, as the
Spring mock does; there is no container, so no error page is rendered.
+/
module flint.mock.web;

import flint.engine.aot.any : Any;
import flint.engine.aot.text : decimal, parseDouble, parseLong;
import flint.http : HttpHeaders, MediaType;
import flint.jakarta.servlet : DispatcherType, Filter, FilterRegistration, RequestDispatcher,
    Servlet, ServletContext, ServletInputStream, ServletOutputStream, ServletRegistration;
import flint.jakarta.servlet.http : Cookie, HttpServletRequest, HttpServletResponse;
import flint.java.io : PrintWriter, Writer;
import flint.java.lang : IllegalArgumentException, IllegalStateException, NumberFormatException,
    UnsupportedOperationException;
import flint.java.util : Locale;
import std.typecons : Nullable;

@safe:

/// `MockServletContext`.
class MockServletContext : ServletContext
{
    private string contextPath = "";
    private Any[string] attributes;

    string getContextPath()
    {
        return contextPath;
    }

    /// Sets the context path.
    void setContextPath(string contextPath) pure nothrow @nogc
    {
        this.contextPath = contextPath;
    }

    Any getAttribute(string name)
    {
        if (auto value = name in attributes)
            return *value;
        return Any.init;
    }

    void setAttribute(string name, Any object)
    {
        attributes[name] = object;
    }

    string getServerInfo()
    {
        return "MockServletContext";
    }

    string getMimeType(string file)
    {
        return null;
    }

    int getMajorVersion()
    {
        return 6;
    }

    int getMinorVersion()
    {
        return 1;
    }

    /// Spring's mock: dynamic registration is unsupported.
    ServletRegistration.Dynamic addServlet(string, Servlet)
    {
        throw new UnsupportedOperationException();
    }

    /// ditto
    FilterRegistration.Dynamic addFilter(string, Filter)
    {
        throw new UnsupportedOperationException();
    }
}

private struct Pair
{
    string name;
    string[] values;
}

pragma(inline, false) private ptrdiff_t findPair(const(Pair)[] pairs, string name, bool ignoreCase) pure nothrow @nogc
{
    foreach (i, ref p; pairs)
        if (ignoreCase ? equalsIgnoreCase(p.name, name) : p.name == name)
            return i;
    return -1;
}

pragma(inline, false) private string firstHeaderValue(const(Pair)[] headers, string name) pure nothrow @nogc
{
    const i = findPair(headers, name, true);
    return i >= 0 && headers[i].values.length != 0 ? headers[i].values[0] : null;
}

pragma(inline, false) private void storeHeaderValue(ref Pair[] headers, string name, string value, bool add)
{
    const index = findPair(headers, name, true);
    if (index < 0)
        headers ~= Pair(name, [value]);
    else if (add)
        headers[index].values ~= value;
    else
        headers[index].values = [value];
}

pragma(inline, false) private string[] pairNames(const(Pair)[] pairs) pure nothrow
{
    string[] names;
    foreach (ref pair; pairs)
        names ~= pair.name;
    return names;
}

pragma(inline, false) private bool tryParseContentType(string type, out MediaType mediaType)
{
    try
        mediaType = MediaType.parseMediaType(type);
    catch (Exception)
        return false;
    return true;
}

private final class BytesInput : ServletInputStream
{
    private const(ubyte)[] content;
    private size_t position;

    this(const(ubyte)[] content) pure nothrow @nogc
    {
        this.content = content;
    }

    override int read()
    {
        return position < content.length ? content[position++] : -1;
    }

    override ubyte[] readAllBytes()
    {
        auto rest = content[position .. $].dup;
        position = content.length;
        return rest;
    }

    override bool isFinished()
    {
        return position >= content.length;
    }

    override bool isReady()
    {
        return true;
    }
}

/// `MockHttpServletRequest`.
class MockHttpServletRequest : HttpServletRequest
{
    private string method = "";
    private string requestURI = "";
    private string contextPath = "";
    private string servletPath = "";
    private string pathInfo;
    private Nullable!string uriTemplate;
    private string queryString;
    private Pair[] parameters;
    private Pair[] headers;
    private string[] attributeNames;
    private Any[string] attributes;
    private const(ubyte)[] content;
    private string characterEncoding;
    private string contentType;
    private Cookie[] cookies;
    private string scheme = "http";
    private string serverName = "localhost";
    private int serverPort = 80;
    private string remoteAddr = "127.0.0.1";
    private string protocol = "HTTP/1.1";
    private DispatcherType dispatcherType = DispatcherType.REQUEST;
    private MockServletContext servletContext;
    private Locale[] locales = [Locale.ENGLISH];

    /// With a method and request URI.
    this(string method = "", string requestURI = "")
    {
        this.method = method;
        this.requestURI = requestURI;
        servletContext = new MockServletContext;
    }

    /// Sets the method.
    void setMethod(string method) pure nothrow @nogc
    {
        this.method = method;
    }

    /// Sets the request URI.
    void setRequestURI(string requestURI) pure nothrow @nogc
    {
        this.requestURI = requestURI;
    }

    /// Sets the context path.
    void setContextPath(string contextPath) pure nothrow @nogc
    {
        this.contextPath = contextPath;
    }

    /// Sets the servlet path.
    void setServletPath(string servletPath) pure nothrow @nogc
    {
        this.servletPath = servletPath;
    }

    /// Sets the nullable path information after the context and servlet paths.
    void setPathInfo(Nullable!string pathInfo) pure nothrow @nogc
    {
        this.pathInfo = pathInfo.isNull ? null : pathInfo.get();
    }

    /// Records the original URI template used to build this request.
    void setUriTemplate(Nullable!string uriTemplate) pure nothrow @nogc
    {
        this.uriTemplate = uriTemplate;
    }

    /// The original URI template, absent for a request built from an explicit URI.
    Nullable!string getUriTemplate() const pure nothrow @nogc
    {
        return uriTemplate;
    }

    /// Sets the query string.
    void setQueryString(string queryString) pure nothrow @nogc
    {
        this.queryString = queryString;
    }

    /// Adds a parameter value.
    void addParameter(string name, string[] values...)
    {
        const i = findPair(parameters, name, false);
        if (i >= 0)
            parameters[i].values ~= values;
        else
            parameters ~= Pair(name, values.dup);
    }

    /// Sets a parameter's values.
    void setParameter(string name, string[] values...)
    {
        const i = findPair(parameters, name, false);
        if (i >= 0)
            parameters[i].values = values.dup;
        else
            parameters ~= Pair(name, values.dup);
    }

    /// Adds a header value; `Content-Type` also sets the content type.
    void addHeader(string name, string value)
    {
        if (equalsIgnoreCase(name, HttpHeaders.CONTENT_TYPE) && contentType is null)
            setContentType(value);
        // Spring's mock: the first Accept-Language header replaces the preferred locales (ENGLISH when empty).
        if (equalsIgnoreCase(name, "Accept-Language") && findPair(headers, name, true) < 0)
        {
            locales = acceptLanguageLocales(value);
            if (locales.length == 0)
                locales = [Locale.ENGLISH];
        }
        storeHeaderValue(headers, name, value, true);
    }

    /// Sets the body.
    void setContent(const(ubyte)[] content) pure nothrow @nogc
    {
        this.content = content;
    }

    /// Sets the content type (and the encoding when it names a charset).
    void setContentType(string contentType)
    {
        this.contentType = contentType;
        if (contentType !is null)
        {
            MediaType mediaType;
            if (tryParseContentType(contentType, mediaType))
            {
                if (auto charset = mediaType.getCharset())
                    characterEncoding = charset.name();
            }
            storeHeaderValue(headers, HttpHeaders.CONTENT_TYPE, contentType, false);
        }
    }

    /// Sets the cookies.
    void setCookies(Cookie[] cookies...) pure nothrow
    {
        this.cookies = cookies.dup;
    }

    /// Sets the dispatcher type.
    void setDispatcherType(DispatcherType dispatcherType) pure nothrow @nogc
    {
        this.dispatcherType = dispatcherType;
    }

    /// Sets the server name.
    void setServerName(string serverName) pure nothrow @nogc
    {
        this.serverName = serverName;
    }

    /// Sets the server port.
    void setServerPort(int serverPort) pure nothrow @nogc
    {
        this.serverPort = serverPort;
    }

    /// Sets the scheme.
    void setScheme(string scheme) pure nothrow @nogc
    {
        this.scheme = scheme;
    }

    /// Sets the remote address.
    void setRemoteAddr(string remoteAddr) pure nothrow @nogc
    {
        this.remoteAddr = remoteAddr;
    }

    /// The body.
    const(ubyte)[] getContentAsByteArray() pure nothrow @nogc
    {
        return content;
    }

    // ----- ServletRequest

    Any getAttribute(string name)
    {
        if (auto value = name in attributes)
            return *value;
        return Any.init;
    }

    string[] getAttributeNames()
    {
        return attributeNames.dup;
    }

    string getCharacterEncoding()
    {
        return characterEncoding;
    }

    void setCharacterEncoding(string env)
    {
        characterEncoding = env;
    }

    int getContentLength()
    {
        return content is null ? -1 : cast(int) content.length;
    }

    long getContentLengthLong()
    {
        return content is null ? -1 : cast(long) content.length;
    }

    string getContentType()
    {
        return contentType;
    }

    ServletInputStream getInputStream()
    {
        return new BytesInput(content);
    }

    string getParameter(string name)
    {
        const i = findPair(parameters, name, false);
        return i >= 0 && parameters[i].values.length != 0 ? parameters[i].values[0] : null;
    }

    string[] getParameterNames()
    {
        return pairNames(parameters);
    }

    string[] getParameterValues(string name)
    {
        const i = findPair(parameters, name, false);
        return i >= 0 ? parameters[i].values : null;
    }

    string[][string] getParameterMap()
    {
        string[][string] map;
        foreach (p; parameters)
            map[p.name] = p.values;
        return map;
    }

    string getProtocol()
    {
        return protocol;
    }

    string getScheme()
    {
        return scheme;
    }

    string getServerName()
    {
        return serverName;
    }

    int getServerPort()
    {
        return serverPort;
    }

    string getRemoteAddr()
    {
        return remoteAddr;
    }

    string getRemoteHost()
    {
        return "localhost";
    }

    void setAttribute(string name, Any o)
    {
        if (o.isNull())
        {
            removeAttribute(name);
            return;
        }
        if (name !in attributes)
            attributeNames ~= name;
        attributes[name] = o;
    }

    void removeAttribute(string name)
    {
        if (name !in attributes)
            return;
        attributes.remove(name);
        foreach (i, n; attributeNames)
            if (n == name)
            {
                attributeNames = attributeNames[0 .. i] ~ attributeNames[i + 1 .. $];
                break;
            }
    }

    bool isSecure()
    {
        return scheme == "https";
    }

    RequestDispatcher getRequestDispatcher(string path)
    {
        return null;
    }

    int getRemotePort()
    {
        return 80;
    }

    string getLocalName()
    {
        return "localhost";
    }

    string getLocalAddr()
    {
        return "127.0.0.1";
    }

    int getLocalPort()
    {
        return 80;
    }

    ServletContext getServletContext()
    {
        return servletContext;
    }

    bool isAsyncSupported()
    {
        return false;
    }

    DispatcherType getDispatcherType()
    {
        return dispatcherType;
    }

    string getRequestId()
    {
        return "";
    }

    string getProtocolRequestId()
    {
        return "";
    }

    /// The preferred locale (`Locale.ENGLISH` unless set).
    Locale getLocale()
    {
        return locales[0];
    }

    /// The preferred locales, most preferred first.
    Locale[] getLocales()
    {
        return locales.dup;
    }

    /// Adds a locale ahead of the others.
    void addPreferredLocale(Locale locale) pure nothrow
    {
        locales = locale ~ locales;
    }

    /// Replaces the preferred locales; at least one is required.
    void setPreferredLocales(Locale[] locales)
    {
        import flint.java.lang : IllegalArgumentException;

        if (locales.length == 0)
            throw new IllegalArgumentException("Locale list must not be empty");
        this.locales = locales.dup;
    }

    // ----- HttpServletRequest

    string getAuthType()
    {
        return null;
    }

    Cookie[] getCookies()
    {
        return cookies.length == 0 ? null : cookies;
    }

    long getDateHeader(string name)
    {
        auto headersView = HttpHeaders.create();
        foreach (value; getHeaders(name))
            headersView.add(name, value);
        return headersView.getFirstDate(name);
    }

    string getHeader(string name)
    {
        return firstHeaderValue(headers, name);
    }

    string[] getHeaders(string name)
    {
        const i = findPair(headers, name, true);
        return i >= 0 ? headers[i].values : null;
    }

    string[] getHeaderNames()
    {
        return pairNames(headers);
    }

    int getIntHeader(string name)
    {
        const value = getHeader(name);
        return value is null ? -1 : cast(int) parseIntegerHeader(value, int.min, int.max);
    }

    string getMethod()
    {
        return method;
    }

    string getPathInfo()
    {
        return pathInfo;
    }

    string getPathTranslated()
    {
        return null;
    }

    string getContextPath()
    {
        return contextPath;
    }

    string getQueryString()
    {
        return queryString;
    }

    string getRemoteUser()
    {
        return null;
    }

    bool isUserInRole(string role)
    {
        return false;
    }

    string getRequestedSessionId()
    {
        return null;
    }

    string getRequestURI()
    {
        return requestURI;
    }

    string getRequestURL()
    {
        const defaultPort = (scheme == "http" && serverPort == 80) || (scheme == "https" && serverPort == 443);
        return scheme ~ "://" ~ serverName ~ (defaultPort ? "" : ":" ~ decimal(serverPort)) ~ requestURI;
    }

    string getServletPath()
    {
        return servletPath;
    }

    bool isRequestedSessionIdValid()
    {
        return false;
    }
}

private final class BytesOutput : ServletOutputStream
{
    private MockHttpServletResponse response;

    this(MockHttpServletResponse response) pure nothrow @nogc
    {
        this.response = response;
    }

    override void write(int b)
    {
        const ubyte[1] bytes = [cast(ubyte) b];
        response.appendContent(bytes[]);
    }

    override void write(scope const(ubyte)[] b)
    {
        if (b.length != 0)
            response.appendContent(b);
    }

    override void flush()
    {
        response.setCommitted(true);
    }
}

private final class ContentWriter : Writer
{
    private MockHttpServletResponse response;
    private bool closed;

    this(MockHttpServletResponse response) pure nothrow @nogc
    {
        this.response = response;
    }

    override void write(scope const(char)[] text)
    {
        if (!closed)
            response.appendContent(cast(const(ubyte)[]) text);
    }

    override void flush()
    {
        response.setCommitted(true);
    }

    override void close()
    {
        closed = true;
        flush();
    }
}

/// `MockHttpServletResponse`.
class MockHttpServletResponse : HttpServletResponse
{
    private enum string defaultEncoding = "ISO-8859-1";
    private enum string charsetPrefix = "charset=";
    private static immutable MediaType applicationPlusJson = MediaType.constant("application", "*+json");

    private int status = HttpServletResponse.SC_OK;
    private string errorMessage;
    private Pair[] headers;
    private string contentType;
    private string defaultCharacterEncoding = defaultEncoding;
    private string characterEncoding = defaultEncoding;
    private bool characterEncodingSet;
    private long contentLength;
    private ubyte[] content;
    private int bufferSize = 4096;
    private bool committed;
    private bool outputStreamAccessAllowed = true;
    private bool writerAccessAllowed = true;
    private Cookie[] cookies;
    private ServletOutputStream outputStream;
    private PrintWriter writer;
    private Locale locale;
    private bool localeSet;

    // ----- inspection

    /// The body bytes.
    const(ubyte)[] getContentAsByteArray() const pure nothrow @nogc
    {
        return content;
    }

    /// The body decoded with the response encoding (`ISO-8859-1` unless set).
    string getContentAsString() const
    {
        return decodeContent(characterEncoding);
    }

    /// The body decoded as `charset` (UTF-8 or ISO-8859-1).
    string getContentAsString(string charset) const
    {
        return decodeContent(charset);
    }

    pragma(inline, false) private string decodeContent(string charset) const
    {
        if (equalsIgnoreCase(charset, "UTF-8"))
            return cast(string) content.idup;
        // ISO-8859-1: each byte is one code point.
        string result;
        foreach (b; content)
            result ~= cast(dchar) b;
        return result;
    }

    /// The `sendError` message, or `null`.
    string getErrorMessage() const pure nothrow @nogc
    {
        return errorMessage;
    }

    /// The first Location header, or `null`.
    string getRedirectedUrl() const pure nothrow @nogc
    {
        return firstHeaderValue(headers, HttpHeaders.LOCATION);
    }

    /// The cookies added.
    Cookie[] getCookies() pure nothrow @nogc
    {
        return cookies;
    }

    /// Marks the response committed.
    void setCommitted(bool committed) pure nothrow @nogc
    {
        this.committed = committed;
    }

    pragma(inline, false) private void appendContent(scope const(ubyte)[] bytes)
    {
        content ~= bytes;
        const limit = getBufferSize();
        if (limit > 0 && content.length > cast(size_t) limit)
            setCommitted(true);
    }

    // ----- ServletResponse

    /// Sets the fallback encoding without marking a charset as explicitly set.
    void setDefaultCharacterEncoding(string encoding)
    {
        requireResponseText(encoding, "'characterEncoding' must not be null");
        defaultCharacterEncoding = encoding;
        if (!characterEncodingSet)
            characterEncoding = encoding;
    }

    /// Whether an explicit charset has been set.
    bool isCharset() const pure nothrow @nogc
    {
        return characterEncodingSet;
    }

    string getCharacterEncoding()
    {
        return characterEncoding;
    }

    string getContentType()
    {
        return contentType;
    }

    /// Controls whether callers may acquire the output stream.
    void setOutputStreamAccessAllowed(bool allowed) pure nothrow @nogc
    {
        outputStreamAccessAllowed = allowed;
    }

    /// Whether callers may acquire the output stream.
    bool isOutputStreamAccessAllowed() const pure nothrow @nogc
    {
        return outputStreamAccessAllowed;
    }

    /// Controls whether callers may acquire the writer.
    void setWriterAccessAllowed(bool allowed) pure nothrow @nogc
    {
        writerAccessAllowed = allowed;
    }

    /// Whether callers may acquire the writer.
    bool isWriterAccessAllowed() const pure nothrow @nogc
    {
        return writerAccessAllowed;
    }

    pragma(inline, false) ServletOutputStream getOutputStream()
    {
        if (!outputStreamAccessAllowed)
            rejectResponseState("OutputStream access not allowed");
        if (writer !is null)
            rejectResponseState("getWriter() has already been called");
        if (outputStream is null)
            outputStream = new BytesOutput(this);
        return outputStream;
    }

    pragma(inline, false) PrintWriter getWriter()
    {
        if (!writerAccessAllowed)
            rejectResponseState("Writer access not allowed");
        if (outputStream !is null)
            rejectResponseState("getOutputStream() has already been called");
        if (writer is null)
            writer = new PrintWriter(new ContentWriter(this));
        return writer;
    }

    void setCharacterEncoding(string charset)
    {
        characterEncodingSet = charset !is null;
        characterEncoding = characterEncodingSet ? charset : defaultCharacterEncoding;
        if (!characterEncodingSet && contentType !is null)
            removeContentTypeCharset();
        updateContentTypeHeader();
    }

    private void removeContentTypeCharset()
    {
        MediaType mediaType;
        if (tryParseContentType(contentType, mediaType))
        {
            if (mediaType.getCharset() is null)
                return;
            const parameters = mediaType.getParameters().entrySet();
            foreach (i, ref entry; parameters)
            {
                if (!equalsIgnoreCase(entry.key, "charset"))
                    continue;
                contentType = MediaType(mediaType, parameters[0 .. i] ~ parameters[i + 1 .. $]).toString();
                return;
            }
        }
        else
        {
            const index = charsetIndex(contentType);
            if (index != contentType.length)
            {
                const remaining = trimAscii(contentType[0 .. index]);
                contentType = remaining.length != 0 && remaining[$ - 1] == ';' ? remaining[0 .. $ - 1] : remaining;
            }
        }
    }

    void setContentLength(int len)
    {
        setContentLengthLong(len);
    }

    void setContentLengthLong(long len)
    {
        if (!isCommitted())
        {
            contentLength = len;
            storeHeaderValue(headers, HttpHeaders.CONTENT_LENGTH, decimal(len), false);
        }
    }

    /// The content length as a Java int.
    int getContentLength() const pure nothrow @nogc
    {
        return cast(int) contentLength;
    }

    /// The content length set, or zero.
    long getContentLengthLong() const pure nothrow @nogc
    {
        return contentLength;
    }

    void setContentType(string type)
    {
        contentType = type;
        if (type !is null)
        {
            MediaType mediaType;
            if (tryParseContentType(type, mediaType))
            {
                if (auto charset = mediaType.getCharset())
                {
                    characterEncoding = charset.name();
                    characterEncodingSet = true;
                }
                else if (mediaType.isCompatibleWith(MediaType.APPLICATION_JSON)
                        || mediaType.isCompatibleWith(applicationPlusJson))
                    characterEncoding = "UTF-8";
            }
            else
            {
                const index = charsetIndex(type);
                if (index != type.length)
                {
                    characterEncoding = type[index + charsetPrefix.length .. $];
                    characterEncodingSet = true;
                }
            }
            updateContentTypeHeader();
        }
        else
        {
            removeHeader(HttpHeaders.CONTENT_TYPE);
        }
    }

    pragma(inline, false) private void updateContentTypeHeader()
    {
        if (contentType is null)
            return;
        string value = contentType;
        if (characterEncodingSet && charsetIndex(value) == value.length)
            value ~= ";" ~ charsetPrefix ~ characterEncoding;
        contentType = value;
        storeHeaderValue(headers, HttpHeaders.CONTENT_TYPE, value, false);
    }

    pragma(inline, false) private static size_t charsetIndex(string type) pure nothrow @nogc
    {
        if (type.length >= charsetPrefix.length)
            foreach (i; 0 .. type.length - charsetPrefix.length + 1)
                if (equalsIgnoreCase(type[i .. i + charsetPrefix.length], charsetPrefix))
                    return i;
        return type.length;
    }

    void setBufferSize(int size)
    {
        bufferSize = size;
    }

    int getBufferSize()
    {
        return bufferSize;
    }

    void flushBuffer()
    {
        setCommitted(true);
    }

    void resetBuffer()
    {
        if (isCommitted())
            rejectResponseState("Cannot reset buffer - response is already committed");
        content = null;
    }

    bool isCommitted()
    {
        return committed;
    }

    /// Sets the locale and `Content-Language`, as Spring's mock does.
    void setLocale(Locale loc)
    {
        locale = loc;
        localeSet = true;
        storeHeaderValue(headers, HttpHeaders.CONTENT_LANGUAGE, loc.toLanguageTag(), false);
    }

    /// Sets the locale when the caller supplied one.
    void setLocale(Nullable!Locale loc)
    {
        if (!loc.isNull)
            setLocale(loc.get());
    }

    /// The locale (the default locale unless set).
    Locale getLocale()
    {
        return localeSet ? locale : Locale.getDefault();
    }

    void reset()
    {
        resetBuffer();
        characterEncoding = defaultCharacterEncoding;
        characterEncodingSet = false;
        contentLength = 0;
        contentType = null;
        localeSet = false;
        cookies = null;
        headers = null;
        status = HttpServletResponse.SC_OK;
        errorMessage = null;
        writer = null;
        outputStream = null;
    }

    // ----- HttpServletResponse

    void addCookie(Cookie cookie)
    {
        cookies ~= cookie;
        addHeader("Set-Cookie", cookie.getName() ~ "=" ~ cookie.getValue());
    }

    bool containsHeader(string name)
    {
        return findPair(headers, name, true) >= 0;
    }

    string encodeURL(string url)
    {
        return url;
    }

    string encodeRedirectURL(string url)
    {
        return url;
    }

    void sendError(int sc, string msg)
    {
        recordError(sc, msg);
    }

    void sendError(int sc)
    {
        recordError(sc, errorMessage);
    }

    pragma(inline, false) private void recordError(int sc, string msg)
    {
        if (isCommitted())
            rejectResponseState("Cannot set error status - response is already committed");
        status = sc;
        errorMessage = msg;
        setCommitted(true);
    }

    void sendRedirect(string location)
    {
        sendRedirect(location, HttpServletResponse.SC_MOVED_TEMPORARILY, true);
    }

    /// Records the redirect and supplied status. As in Spring's mock, either clearBuffer value keeps the body.
    void sendRedirect(string location, int sc, bool clearBuffer)
    {
        if (isCommitted())
            rejectResponseState("Cannot send redirect - response is already committed");
        requireResponseText(location, "Redirect URL must not be null");
        setHeader(HttpHeaders.LOCATION, location);
        setStatus(sc);
        setCommitted(true);
    }

    void setDateHeader(string name, long date)
    {
        setOrAddHeader(name, HttpHeaders.formatDate(date), false);
    }

    void addDateHeader(string name, long date)
    {
        setOrAddHeader(name, HttpHeaders.formatDate(date), true);
    }

    void setHeader(string name, string value)
    {
        setOrAddHeader(name, value, false);
    }

    void addHeader(string name, string value)
    {
        setOrAddHeader(name, value, true);
    }

    void setIntHeader(string name, int value)
    {
        setOrAddHeader(name, decimal(value), false);
    }

    void addIntHeader(string name, int value)
    {
        setOrAddHeader(name, decimal(value), true);
    }

    pragma(inline, false) private void setOrAddHeader(string name, string value, bool add)
    {
        if (name is null)
            return;
        if (equalsIgnoreCase(name, HttpHeaders.CONTENT_TYPE))
            setContentType(value);
        else if (equalsIgnoreCase(name, HttpHeaders.CONTENT_LENGTH))
        {
            if (value is null)
                contentLength = 0;
            else
                setContentLengthLong(parseIntegerHeader(value, long.min, long.max));
        }
        else if (value is null)
            removeHeader(name);
        else if (equalsIgnoreCase(name, HttpHeaders.CONTENT_LANGUAGE))
            setContentLanguage(value, add);
        else
            storeHeaderValue(headers, name, value, add);
    }

    private void setContentLanguage(string value, bool add)
    {
        if (!add || !containsHeader(HttpHeaders.CONTENT_LANGUAGE))
        {
            auto contentHeaders = HttpHeaders.create();
            contentHeaders.add(HttpHeaders.CONTENT_LANGUAGE, value);
            const values = contentHeaders.getValuesAsList(HttpHeaders.CONTENT_LANGUAGE);
            locale = values.length == 0 ? Locale.getDefault() : Locale.forLanguageTag(values[0]);
            localeSet = true;
        }
        storeHeaderValue(headers, HttpHeaders.CONTENT_LANGUAGE, value, add);
    }

    pragma(inline, false) private void removeHeader(string name)
    {
        const i = findPair(headers, name, true);
        if (i < 0)
            return;
        for (size_t position = i + 1; position < headers.length; ++position)
            headers[position - 1] = headers[position];
        headers[$ - 1] = Pair.init;
        headers = headers[0 .. $ - 1];
    }

    void setStatus(int sc)
    {
        if (!isCommitted())
            status = sc;
    }

    int getStatus()
    {
        return status;
    }

    string getHeader(string name)
    {
        return firstHeaderValue(headers, name);
    }

    string[] getHeaders(string name)
    {
        const i = findPair(headers, name, true);
        return i >= 0 ? headers[i].values : null;
    }

    string[] getHeaderNames()
    {
        return pairNames(headers);
    }

}

pragma(inline, false) private noreturn rejectResponseState(string message)
{
    throw new IllegalStateException(message);
}

pragma(inline, false) private void requireResponseText(string value, string message)
{
    if (value is null)
        throw new IllegalArgumentException(message);
}

/// A signed Java decimal header value within the caller's integer range.
pragma(inline, false) private long parseIntegerHeader(string value, long minimum, long maximum)
{
    long parsed;
    if (!parseLong(value, parsed) || parsed < minimum || parsed > maximum)
        throw new NumberFormatException("For input string: \"" ~ value ~ "\"");
    return parsed;
}

/// `value` without leading and trailing ASCII whitespace.
pragma(inline, false) private inout(char)[] trimAscii(return scope inout(char)[] value) pure nothrow @nogc
{
    size_t start;
    size_t end = value.length;
    while (start < end && (value[start] == ' ' || value[start] == '\t'))
        ++start;
    while (end > start && (value[end - 1] == ' ' || value[end - 1] == '\t'))
        --end;
    return value[start .. end];
}

pragma(inline, false) private bool equalsIgnoreCase(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
{
    if (a.length != b.length)
        return false;
    foreach (index, c; a)
    {
        const x = c >= 'A' && c <= 'Z' ? cast(char)(c + 32) : c;
        const y = b[index] >= 'A' && b[index] <= 'Z' ? cast(char)(b[index] + 32) : b[index];
        if (x != y)
            return false;
    }
    return true;
}

/// `HttpHeaders.getAcceptLanguageAsLocales`: the ranges by descending weight (header order within a weight),
/// without `*` and zero-weight ranges.
private Locale[] acceptLanguageLocales(string value)
{
    struct Ranked
    {
        double weight;
        Locale locale;
    }

    Ranked[] ranked;
    size_t start;
    foreach (end; 0 .. value.length + 1)
    {
        if (end != value.length && value[end] != ',')
            continue;
        auto entry = value[start .. end];
        start = end + 1;
        double weight = 1;
        size_t semicolon = entry.length;
        foreach (index, c; entry)
            if (c == ';')
            {
                semicolon = index;
                break;
            }
        if (semicolon < entry.length)
        {
            const parameter = trimAscii(entry[semicolon + 1 .. $]);
            if (parameter.length > 2 && parameter[0 .. 2] == "q=" && !parseDouble(parameter[2 .. $], weight))
                continue;
        }
        const range = trimAscii(entry[0 .. semicolon]);
        if (range.length == 0 || range == "*" || !(weight > 0))
            continue;
        ranked ~= Ranked(weight, Locale.forLanguageTag(range));
    }
    foreach (i; 1 .. ranked.length)
    {
        const item = ranked[i];
        size_t j = i;
        while (j > 0 && ranked[j - 1].weight < item.weight)
        {
            ranked[j] = ranked[j - 1];
            --j;
        }
        ranked[j] = item;
    }
    Locale[] result;
    foreach (item; ranked)
        result ~= item.locale;
    return result;
}
