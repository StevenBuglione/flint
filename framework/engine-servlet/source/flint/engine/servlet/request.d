/++
The servlet engine's `HttpServletRequest`: a GC copy of one `flint.engine.web` request.

The engine copies the request line, every field and the body out of the request arena in two allocations before
the servlet runs, so no arena memory reaches application code (ADR-030 section 4). Everything a getter returns is
a slice of that copy or a value derived from it. The behaviour follows Tomcat's `org.apache.catalina.connector.Request`
as Spring Boot 4.2.0 runs it: parameters come from the query string, decoded as UTF-8 with `+` as a space, and from
an `application/x-www-form-urlencoded` body; the servlet mapped at `/` sees the whole path as its servlet path.
+/
module flint.engine.servlet.request;

import flint.engine.servlet.exchange : Access, PooledState;
import flint.engine.aot.any : Any;
import flint.engine.web.types : Method;
import flint.jakarta.servlet : DispatcherType, RequestDispatcher, ServletContext,
    ServletInputStream, ServletRequest, ServletResponse;
import flint.jakarta.servlet.http : Cookie, HeaderFieldSource, HttpServletRequest;
import flint.java.lang : IllegalArgumentException, IllegalStateException, NumberFormatException;
import flint.java.util : Locale;

@safe:

/// What a request reads from its engine: the servlet context, the listener and a dispatcher factory.
package(flint.engine.servlet) interface RequestHost
{
    ServletContext context();
    string localAddress();
    int localPort();
    RequestDispatcher dispatcher(string path);
}

private struct Attribute
{
    string name;
    Any value;
}

// The first growth past the eight inline slots (setAttribute) stays within druntime's 1,024-byte size class.
static assert((8 * 7 / 4) * Attribute.sizeof <= 1024);

private struct Parameter
{
    string name;
    string first;
    string[] rest;

    /// A new array of every value, as `getParameterValues` returns.
    string[] values() const pure nothrow
    {
        auto all = new string[1 + rest.length];
        all[0] = first;
        all[1 .. $] = rest[];
        return all;
    }
}

/// The request a servlet sees for one exchange on the servlet engine.
final class ServletEngineRequest : HttpServletRequest, HeaderFieldSource
{
    // A handle: everything this exchange says or changes (the request line, the fields and body, redirects,
    // attributes and parameters) lives in its pooled RequestState, checked out with `stateGeneration`
    // (flint.engine.servlet.exchange). Once the exchange has completed, every method throws (owner decision (a)).
    private RequestHost host;
    private RequestState state;
    private ulong stateGeneration;

    package(flint.engine.servlet) this(RequestHost host, string method, string requestURI, string queryString,
            string protocol, string contextPath, string[] names, string[] values,
            immutable(ubyte)[] content, ulong requestNumber, RequestState state, ulong generation)
    {
        this.state = state;
        stateGeneration = generation;
        this.host = host;
        state.method = method;
        state.requestURI = requestURI;
        state.queryString = queryString;
        state.protocol = protocol;
        state.contextPath = contextPath;
        state.servletPath = requestURI.length >= contextPath.length ? requestURI[contextPath.length .. $] : requestURI;
        state.names = names;
        state.values = values;
        state.content = content;
        state.requestNumber = requestNumber;
    }

    /// The pooled state and its generation, for the engine's return at the end of the exchange.
    package(flint.engine.servlet) RequestState pooledState(out ulong generation) pure nothrow @nogc
    {
        generation = stateGeneration;
        return state;
    }

    // Entered by every method user code can reach: throws once the exchange has completed.
    private Access enter()
    {
        return Access(state, stateGeneration, "request");
    }

    /// Storage for `length` field names and values: in the state's slots when they fit.
    package(flint.engine.servlet) string[] fieldStorage(size_t length) return
    {
        return length <= state.inlineFields.length ? state.inlineFields[0 .. length] : new string[length];
    }

    /// The fields and body `ServletEngine.capture` copied out of the request arena.
    package(flint.engine.servlet) void setCaptured(string[] names, string[] values, immutable(ubyte)[] content)
    {
        state.names = names;
        state.values = values;
        state.content = content;
    }

    /// Change the path the request reports, as a forward or error dispatch does; returns the previous state.
    package(flint.engine.servlet) DispatchState redirect(string uri, string query, DispatcherType type)
    {
        auto previous = DispatchState(state.requestURI, state.servletPath, state.queryString, state.dispatcherType);
        state.requestURI = state.contextPath ~ uri;
        state.servletPath = uri;
        state.queryString = query;
        state.dispatcherType = type;
        return previous;
    }

    /// Restore the state `redirect` returned.
    package(flint.engine.servlet) void restore(DispatchState state)
    {
        state.requestURI = state.requestURI;
        state.servletPath = state.servletPath;
        state.queryString = state.queryString;
        state.dispatcherType = state.dispatcherType;
    }

    // ServletRequest

    Any getAttribute(string name)
    {
        auto access = enter();
        const index = attributeIndex(name);
        return index < state.attributeCount ? state.attributeSlots[index].value : Any.init;
    }

    string[] getAttributeNames()
    {
        auto access = enter();
        auto list = new string[state.attributeCount];
        foreach (index, ref attribute; state.attributeSlots[0 .. state.attributeCount])
            list[index] = attribute.name;
        return list;
    }

    private size_t attributeIndex(scope const(char)[] name) const pure nothrow @nogc
    {
        foreach (index, ref attribute; state.attributeSlots[0 .. state.attributeCount])
            if (attribute.name.length == name.length && (attribute.name.ptr is name.ptr || attribute.name == name))
                return index;
        return state.attributeCount;
    }

    string getCharacterEncoding()
    {
        auto access = enter();
        if (state.characterEncoding !is null)
            return state.characterEncoding;
        return charsetOf(getContentType());
    }

    void setCharacterEncoding(string env)
    {
        auto access = enter();
        if (!state.parametersParsed && !state.inputUsed)
            state.characterEncoding = env;
    }

    int getContentLength()
    {
        auto access = enter();
        const length = getContentLengthLong();
        return length > int.max ? -1 : cast(int) length;
    }

    long getContentLengthLong()
    {
        auto access = enter();
        const text = getHeader("content-length");
        if (text is null)
            return state.content.length != 0 ? cast(long) state.content.length : -1;
        long value;
        foreach (c; text)
        {
            if (c < '0' || c > '9')
                return -1;
            value = value * 10 + (c - '0');
        }
        return value;
    }

    string getContentType()
    {
        auto access = enter();
        return getHeader("content-type");
    }

    ServletInputStream getInputStream()
    {
        auto access = enter();
        state.inputUsed = true;
        return new BodyInput(state.content, this);
    }

    string getParameter(string name)
    {
        auto access = enter();
        parseParameters();
        const index = parameterAt(name);
        return index < state.parameterCount ? state.parameterSlots[index].first : null;
    }

    string[] getParameterNames()
    {
        auto access = enter();
        parseParameters();
        auto list = new string[state.parameterCount];
        foreach (index, ref parameter; state.parameterSlots[0 .. state.parameterCount])
            list[index] = parameter.name;
        return list;
    }

    string[] getParameterValues(string name)
    {
        auto access = enter();
        parseParameters();
        const index = parameterAt(name);
        return index < state.parameterCount ? state.parameterSlots[index].values() : null;
    }

    string[][string] getParameterMap()
    {
        auto access = enter();
        parseParameters();
        string[][string] copy;
        foreach (ref parameter; state.parameterSlots[0 .. state.parameterCount])
            copy[parameter.name] = parameter.values();
        return copy;
    }

    string getProtocol()
    {
        auto access = enter();
        return state.protocol;
    }

    string getScheme()
    {
        auto access = enter();
        return "http";
    }

    string getServerName()
    {
        auto access = enter();
        const authority = getHeader("host");
        if (authority is null || authority.length == 0)
            return host.localAddress();
        if (authority[0] == '[')
        {
            foreach (index, c; authority)
                if (c == ']')
                    return authority[0 .. index + 1];
            return authority;
        }
        foreach (index, c; authority)
            if (c == ':')
                return authority[0 .. index];
        return authority;
    }

    int getServerPort()
    {
        auto access = enter();
        const authority = getHeader("host");
        if (authority is null || authority.length == 0)
            return host.localPort();
        size_t colon = size_t.max;
        foreach (index, c; authority)
        {
            if (c == ']')
                colon = size_t.max;
            else if (c == ':')
                colon = index;
        }
        if (colon == size_t.max)
            return 80;
        int port;
        foreach (c; authority[colon + 1 .. $])
        {
            if (c < '0' || c > '9' || port > 65_535)
                return 80;
            port = port * 10 + (c - '0');
        }
        return port;
    }

    /// The engine does not expose the peer address yet; `null`, as for a request without one.
    string getRemoteAddr()
    {
        auto access = enter();
        return null;
    }

    /// ditto
    string getRemoteHost()
    {
        auto access = enter();
        return null;
    }

    void setAttribute(string name, Any o)
    {
        auto access = enter();
        if (o.isNull())
        {
            removeAttribute(name);
            return;
        }
        const index = attributeIndex(name);
        if (index < state.attributeCount)
        {
            state.attributeSlots[index].value = o;
            return;
        }
        // A copy on the GC heap (inline slots cannot grow), by 7/4: the first, eight to fourteen 72-byte slots, fills
        // druntime's 1,024-byte size class, where doubling to sixteen took a 1,360-byte block. A 404's error forward
        // sets about a dozen attributes (R-83).
        if (state.attributeCount == state.attributeSlots.length)
        {
            const grown = state.attributeCount * 7 / 4;
            // The state keeps the first overflow block across exchanges, so a request that outgrows the inline slots
            // usually reuses it instead of allocating.
            if (state.attributeSlots.ptr is state.inlineAttributes.ptr && state.attributeBlock.length >= grown)
            {
                state.attributeBlock[0 .. state.attributeCount] = state.attributeSlots[];
                state.attributeSlots = state.attributeBlock;
            }
            else
            {
                const first = state.attributeSlots.ptr is state.inlineAttributes.ptr;
                auto block = new Attribute[grown];
                block[0 .. state.attributeCount] = state.attributeSlots[];
                state.attributeSlots = block;
                if (first && state.attributeBlock.length == 0)
                    state.attributeBlock = block;
            }
        }
        state.attributeSlots[state.attributeCount++] = Attribute(name, o);
    }

    /// `HttpServletRequest.removeAttribute`.
    void removeAttribute(string name)
    {
        auto access = enter();
        const index = attributeIndex(name);
        if (index == state.attributeCount)
            return;
        foreach (later; index + 1 .. state.attributeCount)
            state.attributeSlots[later - 1] = state.attributeSlots[later];
        state.attributeSlots[--state.attributeCount] = Attribute.init;
    }

    /// `HttpServletRequest.isSecure`.
    bool isSecure()
    {
        auto access = enter();
        return false;
    }

    RequestDispatcher getRequestDispatcher(string path)
    {
        auto access = enter();
        if (path is null)
            return null;
        if (path.length == 0 || path[0] != '/')
        {
            // Relative to the current servlet path's directory.
            size_t slash;
            foreach (index, c; state.servletPath)
                if (c == '/')
                    slash = index;
            path = state.servletPath[0 .. slash + 1] ~ path;
        }
        return host.dispatcher(path);
    }

    /// See `getRemoteAddr`.
    int getRemotePort()
    {
        auto access = enter();
        return -1;
    }

    string getLocalName()
    {
        auto access = enter();
        return host.localAddress();
    }

    string getLocalAddr()
    {
        auto access = enter();
        return host.localAddress();
    }

    int getLocalPort()
    {
        auto access = enter();
        return host.localPort();
    }

    ServletContext getServletContext()
    {
        auto access = enter();
        return host.context();
    }

    /// `HttpServletRequest.isAsyncSupported`.
    bool isAsyncSupported()
    {
        auto access = enter();
        return false;
    }

    DispatcherType getDispatcherType()
    {
        auto access = enter();
        return state.dispatcherType;
    }

    string getRequestId()
    {
        auto access = enter();
        // Formatted on demand: most requests never ask for it.
        return decimal(cast(long) state.requestNumber);
    }

    /// HTTP/1 has no protocol-level request id.
    string getProtocolRequestId()
    {
        auto access = enter();
        return "";
    }

    /// `HttpServletRequest.getLocale`: Tomcat's first `Accept-Language` locale, else the default locale.
    Locale getLocale()
    {
        auto access = enter();
        return getLocales()[0];
    }

    /// `HttpServletRequest.getLocales`.
    Locale[] getLocales()
    {
        auto access = enter();
        auto locales = acceptLanguages(getHeaders("accept-language"));
        return locales.length != 0 ? locales : [Locale.getDefault()];
    }

    // HttpServletRequest

    string getAuthType()
    {
        auto access = enter();
        return null;
    }

    Cookie[] getCookies()
    {
        auto access = enter();
        Cookie[] cookies;
        foreach (index, name; state.names)
        {
            if (name != "cookie")
                continue;
            foreach (pair; splitter(state.values[index], ';'))
            {
                const text = trim(pair);
                size_t equals = text.length;
                foreach (position, c; text)
                {
                    if (c == '=')
                    {
                        equals = position;
                        break;
                    }
                }
                if (equals == 0 || equals == text.length)
                    continue;
                auto value = text[equals + 1 .. $];
                if (value.length >= 2 && value[0] == '"' && value[$ - 1] == '"')
                    value = value[1 .. $ - 1];
                try
                    cookies ~= new Cookie(text[0 .. equals], value);
                catch (IllegalArgumentException)
                {
                    // Tomcat drops a cookie whose name is not a token.
                }
            }
        }
        return cookies.length != 0 ? cookies : null;
    }

    long getDateHeader(string name)
    {
        auto access = enter();
        const text = getHeader(name);
        if (text is null)
            return -1;
        const parsed = parseHttpDate(text);
        if (parsed == long.min)
            throw new IllegalArgumentException(text);
        return parsed;
    }

    string getHeader(string name)
    {
        auto access = enter();
        foreach (index, existing; state.names)
            if (equalsIgnoreCase(existing, name))
                return state.values[index];
        return null;
    }

    /// Each header field as received, in order, repeated names included (`HeaderFieldSource`).
    void visitHeaderFields(scope void delegate(string name, string value) @safe visit)
    {
        auto access = enter();
        foreach (index, name; state.names)
            visit(name, state.values[index]);
    }

    string[] getHeaders(string name)
    {
        auto access = enter();
        // Counted first, so the result is one exact allocation, or none when the field is absent.
        size_t count;
        foreach (existing; state.names)
            count += equalsIgnoreCase(existing, name);
        if (count == 0)
            return null;
        auto found = new string[count];
        size_t at;
        foreach (index, existing; state.names)
            if (equalsIgnoreCase(existing, name))
                found[at++] = state.values[index];
        return found;
    }

    string[] getHeaderNames()
    {
        auto access = enter();
        string[] distinct;
        outer: foreach (name; state.names)
        {
            foreach (seen; distinct)
                if (seen == name)
                    continue outer;
            distinct ~= name;
        }
        return distinct;
    }

    int getIntHeader(string name)
    {
        auto access = enter();
        const text = getHeader(name);
        if (text is null)
            return -1;
        long value;
        const negative = text.length != 0 && text[0] == '-';
        const digits = negative ? text[1 .. $] : text;
        if (digits.length == 0)
            throw new NumberFormatException("For input string: \"" ~ text ~ "\"");
        foreach (c; digits)
        {
            if (c < '0' || c > '9' || value > int.max)
                throw new NumberFormatException("For input string: \"" ~ text ~ "\"");
            value = value * 10 + (c - '0');
        }
        value = negative ? -value : value;
        if (value > int.max || value < int.min)
            throw new NumberFormatException("For input string: \"" ~ text ~ "\"");
        return cast(int) value;
    }

    string getMethod()
    {
        auto access = enter();
        return state.method;
    }

    /// The servlet mapped at `/` has no path info.
    string getPathInfo()
    {
        auto access = enter();
        return null;
    }

    string getPathTranslated()
    {
        auto access = enter();
        return null;
    }

    string getContextPath()
    {
        auto access = enter();
        return state.contextPath;
    }

    string getQueryString()
    {
        auto access = enter();
        return state.queryString;
    }

    string getRemoteUser()
    {
        auto access = enter();
        return null;
    }

    /// `HttpServletRequest.isUserInRole`.
    bool isUserInRole(string)
    {
        auto access = enter();
        return false;
    }

    string getRequestedSessionId()
    {
        auto access = enter();
        return null;
    }

    string getRequestURI()
    {
        auto access = enter();
        return state.requestURI;
    }

    string getRequestURL()
    {
        auto access = enter();
        const port = getServerPort();
        const name = getServerName();
        if (port == 80)
            return "http://" ~ name ~ state.requestURI;
        return httpURL(name, port, state.requestURI);
    }

    string getServletPath()
    {
        auto access = enter();
        return state.servletPath;
    }

    /// `HttpServletRequest.isRequestedSessionIdValid`.
    bool isRequestedSessionIdValid()
    {
        auto access = enter();
        return false;
    }

    private void parseParameters()
    {
        if (state.parametersParsed)
            return;
        state.parametersParsed = true;
        addParameters(state.queryString);
        if (state.method == "POST" && !state.inputUsed && state.content.length != 0)
        {
            const type = getContentType();
            if (type !is null && equalsIgnoreCase(trim(splitter(type, ';').front), "application/x-www-form-urlencoded"))
                addParameters(cast(string) state.content);
        }
    }

    private void addParameters(string text)
    {
        if (text.length == 0)
            return;
        foreach (pair; splitter(text, '&'))
        {
            if (pair.length == 0)
                continue;
            size_t equals = pair.length;
            foreach (index, c; pair)
            {
                if (c == '=')
                {
                    equals = index;
                    break;
                }
            }
            const name = decodeComponent(pair[0 .. equals]);
            const value = equals < pair.length ? decodeComponent(pair[equals + 1 .. $]) : "";
            // Tomcat skips a parameter whose name or value is not valid percent-encoding.
            if (name is null || value is null || name.length == 0)
                continue;
            addParameter(name, value);
        }
    }

    private void addParameter(string name, string value)
    {
        const index = parameterAt(name);
        if (index < state.parameterCount)
        {
            state.parameterSlots[index].rest ~= value;
            return;
        }
        if (state.parameterCount == state.parameterSlots.length)
            state.parameterSlots.length = state.parameterCount * 2;
        state.parameterSlots[state.parameterCount++] = Parameter(name, value);
        if (state.parameterIndex !is null)
            state.parameterIndex[name] = state.parameterCount - 1;
        else if (state.parameterCount > indexedParameters)
            foreach (at, ref parameter; state.parameterSlots[0 .. state.parameterCount])
                state.parameterIndex[parameter.name] = at;
    }

    private enum indexedParameters = 16;

    private size_t parameterAt(scope const(char)[] name) const pure nothrow
    {
        if (state.parameterIndex !is null)
        {
            if (auto found = name in state.parameterIndex)
                return *found;
            return state.parameterCount;
        }
        foreach (index, ref parameter; state.parameterSlots[0 .. state.parameterCount])
            if (parameter.name == name)
                return index;
        return state.parameterCount;
    }
}

/// The path state a dispatch replaces.
package(flint.engine.servlet) struct DispatchState
{
    string requestURI;
    string servletPath;
    string queryString;
    DispatcherType dispatcherType;
}

/// The request method as a servlet sees it.
package(flint.engine.servlet) string methodName(Method method) pure nothrow @nogc
{
    final switch (method)
    {
    case Method.get:
        return "GET";
    case Method.post:
        return "POST";
    case Method.put:
        return "PUT";
    case Method.patch:
        return "PATCH";
    case Method.delete_:
        return "DELETE";
    case Method.head:
        return "HEAD";
    case Method.options:
        return "OPTIONS";
    }
}

private final class BodyInput : ServletInputStream
{
    private immutable(ubyte)[] content;
    private size_t position;
    // Its request: the stream stops working with it, once the exchange has completed (owner decision (a), R3).
    private ServletEngineRequest request;

    this(immutable(ubyte)[] content, ServletEngineRequest request) pure nothrow @nogc
    {
        this.content = content;
        this.request = request;
    }

    override int read()
    {
        auto access = request.enter();
        return position < content.length ? content[position++] : -1;
    }

    override ubyte[] readAllBytes()
    {
        auto access = request.enter();
        auto rest = content[position .. $].dup;
        position = content.length;
        return rest;
    }

    override bool isFinished()
    {
        auto access = request.enter();
        return position >= content.length;
    }

    override bool isReady()
    {
        auto access = request.enter();
        return true;
    }
}

/// Decode `application/x-www-form-urlencoded` text: `+` is a space and `%XX` a byte. `null` when malformed.
package(flint.engine.servlet) string decodeComponent(string text) pure nothrow
{
    bool plain = true;
    foreach (c; text)
        if (c == '%' || c == '+')
            plain = false;
    if (plain)
        return text;
    auto output = new char[text.length];
    const length = decodeComponentInto(text, output);
    return length < 0 ? null : output[0 .. length].idup;
}

/// `decodeComponentInto`: `text` is not valid percent-encoding.
package(flint.engine.servlet) enum ptrdiff_t malformedComponent = -1;
/// `decodeComponentInto`: the decoded text does not fit `output`.
package(flint.engine.servlet) enum ptrdiff_t componentTooLong = -2;

/++
The one decoder of `application/x-www-form-urlencoded` text, into `output` without allocating: the decoded length,
`malformedComponent` or `componentTooLong`. `decodeComponent` and the fast path's parameters both use it.
+/
package(flint.engine.servlet) ptrdiff_t decodeComponentInto(scope const(char)[] text, scope char[] output)
    pure nothrow @nogc
{
    if (text.length > output.length)
        return componentTooLong;
    size_t length;
    for (size_t index; index < text.length; ++index)
    {
        const c = text[index];
        if (c == '+')
            output[length++] = ' ';
        else if (c == '%')
        {
            if (index + 2 >= text.length)
                return malformedComponent;
            const high = hexValue(text[index + 1]);
            const low = hexValue(text[index + 2]);
            if (high < 0 || low < 0)
                return malformedComponent;
            output[length++] = cast(char)(high * 16 + low);
            index += 2;
        }
        else
            output[length++] = c;
    }
    return length;
}

private int hexValue(char c) pure nothrow @nogc
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}

/// The `charset` parameter of a media type, or `null`.
package(flint.engine.servlet) string charsetOf(string contentType) pure nothrow
{
    if (contentType is null)
        return null;
    auto parameters = splitter(contentType, ';');
    parameters.popFront();
    foreach (parameter; parameters)
    {
        const text = trim(parameter);
        if (text.length > 8 && equalsIgnoreCase(text[0 .. 8], "charset="))
        {
            auto value = trim(text[8 .. $]);
            if (value.length >= 2 && value[0] == '"' && value[$ - 1] == '"')
                value = value[1 .. $ - 1];
            return value;
        }
    }
    return null;
}

/// Parse an IMF-fixdate (`Sun, 06 Nov 1994 08:49:37 GMT`) into milliseconds since the epoch; `long.min` if not one.
package(flint.engine.servlet) long parseHttpDate(string text) pure nothrow @nogc
{
    static immutable string months = "JanFebMarAprMayJunJulAugSepOctNovDec";
    if (text.length != 29 || text[3 .. 5] != ", " || text[25 .. 29] != " GMT")
        return long.min;
    int number(size_t from, size_t count)
    {
        int value;
        foreach (c; text[from .. from + count])
        {
            if (c < '0' || c > '9')
                return -1;
            value = value * 10 + (c - '0');
        }
        return value;
    }

    const day = number(5, 2), year = number(12, 4), hour = number(17, 2), minute = number(20, 2),
        second = number(23, 2);
    int month = -1;
    foreach (index; 0 .. 12)
        if (text[8 .. 11] == months[index * 3 .. index * 3 + 3])
            month = index + 1;
    if (day < 1 || year < 0 || hour < 0 || minute < 0 || second < 0 || month < 0)
        return long.min;
    // Civil date to days since the epoch (H. Hinnant).
    const y = month <= 2 ? year - 1 : year;
    const era = (y >= 0 ? y : y - 399) / 400;
    const yearOfEra = y - era * 400;
    const dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
    const dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear;
    const days = cast(long) era * 146_097 + dayOfEra - 719_468;
    return ((days * 24 + hour) * 60 + minute) * 60_000L + second * 1000L;
}

package(flint.engine.servlet) bool equalsIgnoreCase(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
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

/// The parts of `text` between `separator`s, as slices of it, without allocating: "a;b;" gives "a", "b" and "".
package(flint.engine.servlet) Splitter splitter(string text, char separator) pure nothrow @nogc
{
    return Splitter(text, separator);
}

/// ditto
package(flint.engine.servlet) struct Splitter
{
    private string rest;
    private char separator;
    private bool last;
    /// The current part.
    string front;
    /// Whether every part has been visited.
    bool empty;

    private this(string text, char separator) pure nothrow @nogc
    {
        rest = text;
        this.separator = separator;
        popFront();
    }

    /// Advance to the next part.
    void popFront() pure nothrow @nogc
    {
        if (last)
        {
            empty = true;
            return;
        }
        foreach (index, c; rest)
        {
            if (c == separator)
            {
                front = rest[0 .. index];
                rest = rest[index + 1 .. $];
                return;
            }
        }
        front = rest;
        last = true;
    }
}

@("splitter yields the same parts as splitting into an array")
unittest
{
    string[] parts(string text, char separator)
    {
        string[] result;
        foreach (part; splitter(text, separator))
            result ~= part;
        return result;
    }

    assert(parts("a=1&b=2", '&') == ["a=1", "b=2"]);
    assert(parts("text/plain; charset=UTF-8;", ';') == ["text/plain", " charset=UTF-8", ""]);
    assert(parts("", ';') == [""]);
    assert(parts("x", ';') == ["x"]);
    assert(parts(";", ';') == ["", ""]);
}

package(flint.engine.servlet) string trim(string text) pure nothrow @nogc
{
    size_t first, last = text.length;
    while (first < last && (text[first] == ' ' || text[first] == '\t'))
        ++first;
    while (last > first && (text[last - 1] == ' ' || text[last - 1] == '\t'))
        --last;
    return text[first .. last];
}

package(flint.engine.servlet) string decimal(long value) pure nothrow
{
    if (value == 0)
        return "0";
    char[20] digits = void;
    return decimalDigits(value, digits).idup;
}

/// `http://name:port` and `path`, in one allocation (a strongly pure result converts to `string`). Written by hand:
/// a concatenation mixing `string` and `char[]` operands allocates once per operator.
private char[] httpURL(string name, long port, string path) pure nothrow
{
    enum scheme = "http://";
    char[20] digits = void;
    const number = decimalDigits(port, digits);
    auto url = new char[scheme.length + name.length + 1 + number.length + path.length];
    size_t at;
    void put(scope const(char)[] part) pure nothrow @nogc
    {
        url[at .. at + part.length] = part[];
        at += part.length;
    }

    put(scheme);
    put(name);
    put(":");
    put(number);
    put(path);
    return url;
}

@("the request URL names a non-default port")
unittest
{
    assert(httpURL("localhost", 8080, "/ctx/a") == "http://localhost:8080/ctx/a");
    assert(httpURL("h", -1, "") == "http://h:-1");
}

/// `value` in decimal with its sign, written at the end of `digits` (long.min needs all twenty); the part written.
private char[] decimalDigits(long value, return ref char[20] digits) pure nothrow @nogc
{
    size_t first = digits.length;
    const negative = value < 0;
    ulong magnitude = negative ? -cast(ulong) value : cast(ulong) value;
    do
    {
        digits[--first] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }
    while (magnitude != 0);
    if (negative)
        digits[--first] = '-';
    return digits[first .. $];
}

@("decimal formats zero, signs and both extremes in one allocation")
unittest
{
    assert(decimal(0) == "0");
    assert(decimal(7) == "7");
    assert(decimal(-42) == "-42");
    assert(decimal(long.max) == "9223372036854775807");
    assert(decimal(long.min) == "-9223372036854775808");
}

@("form decoding treats + as a space, decodes UTF-8 percent bytes and rejects malformed escapes")
unittest
{
    assert(decodeComponent("Jane+Q%20Public") == "Jane Q Public");
    assert(decodeComponent("%C3%A9t%C3%A9") == "été");
    assert(decodeComponent("%22quoted%22%5Cslash%3C%3E") == `"quoted"\slash<>`);
    assert(decodeComponent("plain") == "plain");
    assert(decodeComponent("bad%2") is null);
    assert(decodeComponent("bad%zz") is null);
    assert(decodeComponent("%") is null);
}

@("IMF-fixdate parsing matches the RFC example and rejects other forms")
unittest
{
    assert(parseHttpDate("Sun, 06 Nov 1994 08:49:37 GMT") == 784_111_777_000L);
    assert(parseHttpDate("Thu, 01 Jan 1970 00:00:00 GMT") == 0);
    assert(parseHttpDate("Tue, 29 Feb 2000 00:00:00 GMT") == 951_782_400_000L);
    assert(parseHttpDate("Sunday, 06-Nov-94 08:49:37 GMT") == long.min);
    assert(parseHttpDate("Sun, 06 Nov 1994 08:49:37 UTC") == long.min);
}

@("charset parameters are found in any case and unquoted")
unittest
{
    assert(charsetOf("text/html;charset=UTF-8") == "UTF-8");
    assert(charsetOf("text/plain; Charset=\"iso-8859-1\"") == "iso-8859-1");
    assert(charsetOf("application/json") is null);
    assert(charsetOf(null) is null);
}

/// Tomcat's `Request.parseLocalesHeader`: every `Accept-Language` range with a positive quality, highest quality
/// first and in header order within one quality; `*` and malformed ranges are skipped.
package(flint.engine.servlet) Locale[] acceptLanguages(string[] values)
{
    struct Ranked
    {
        double quality;
        Locale locale;
    }

    Ranked[] ranked;
    foreach (value; values)
    {
        foreach (entry; splitter(value, ','))
        {
            auto parts = splitter(entry, ';');
            const range = trim(parts.front);
            parts.popFront();
            double quality = 1;
            foreach (parameter; parts)
            {
                const text = trim(parameter);
                if (text.length > 2 && (text[0] == 'q' || text[0] == 'Q') && text[1] == '=')
                    quality = parseQuality(text[2 .. $]);
            }
            if (range.length == 0 || range == "*" || !(quality > 0))
                continue;
            const locale = Locale.forLanguageTag(range);
            if (locale.getLanguage().length != 0)
                ranked ~= Ranked(quality, locale);
        }
    }
    // A stable insertion sort by descending quality; header lists are short.
    foreach (i; 1 .. ranked.length)
    {
        const item = ranked[i];
        size_t j = i;
        while (j > 0 && ranked[j - 1].quality < item.quality)
        {
            ranked[j] = ranked[j - 1];
            --j;
        }
        ranked[j] = item;
    }
    Locale[] locales;
    foreach (item; ranked)
        locales ~= item.locale;
    return locales;
}

/// A quality value (`0`, `0.5`, `1.000`); NaN when malformed.
private double parseQuality(string text) pure nothrow @nogc
{
    double value = 0;
    double scale = 0;
    foreach (c; text)
    {
        if (c == '.' && scale == 0)
            scale = 1;
        else if (c >= '0' && c <= '9')
        {
            if (scale == 0)
                value = value * 10 + (c - '0');
            else
            {
                scale /= 10;
                value += (c - '0') * scale;
            }
        }
        else
            return double.nan;
    }
    return text.length == 0 || value > 1 ? double.nan : value;
}

@("Accept-Language orders by quality, keeps header order within a quality and skips q=0, * and bad ranges")
unittest
{
    auto locales = acceptLanguages([
        "fr-CH, fr;q=0.9, en;q=0.8, de;q=0.7, *;q=0.5", "es;q=0, it;q=0.9"
    ]);
    assert(locales.length == 5);
    assert(locales[0].toLanguageTag() == "fr-CH" && locales[1].toLanguageTag() == "fr");
    assert(locales[2].toLanguageTag() == "it" && locales[3].toLanguageTag() == "en");
    assert(locales[4].toLanguageTag() == "de");
    assert(acceptLanguages(["en;q=x"]).length == 0 && acceptLanguages(null).length == 0);
}

/// The pooled storage of one request (flint.engine.servlet.exchange): what used to make each request 1.3 KB.
package(flint.engine.servlet) final class RequestState : PooledState
{
    string[16] inlineFields; /// eight field names and values
    Attribute[8] inlineAttributes; ///
    /// The first attribute overflow block (fourteen slots, a 1,024-byte block), kept across exchanges.
    Attribute[] attributeBlock;
    Parameter[4] inlineParameters; ///

    // Everything one exchange's request says or changes, behind its façade (a handle of a few words).
    string method; ///
    string requestURI; /// as a forward or error dispatch reports it
    string queryString; ///
    string protocol; ///
    string servletPath; ///
    string contextPath; ///
    /// The field names and values, in `inlineFields` when they fit (eight, as Tomcat's MimeHeaders starts with).
    string[] names;
    string[] values; /// ditto
    immutable(ubyte)[] content; /// the body, frozen with the head
    ulong requestNumber; ///
    DispatcherType dispatcherType = DispatcherType.REQUEST; ///
    bool parametersParsed; ///
    bool inputUsed; ///
    /// A request holds a handful of attributes: slots in insertion order (getAttributeNames' order), in
    /// `inlineAttributes` until they outgrow them, then in `attributeBlock` or the GC heap.
    Attribute[] attributeSlots;
    size_t attributeCount; ///
    /// The parameters in the order they arrive (Tomcat's LinkedHashMap order): in `inlineParameters` until they
    /// outgrow it. They are found by a scan while there are few and through `parameterIndex` once there are many,
    /// so a request with thousands of names stays linear.
    Parameter[] parameterSlots;
    size_t parameterCount; ///
    size_t[string] parameterIndex; ///
    /// What `setCharacterEncoding` set, else null.
    string characterEncoding;

    this() nothrow
    {
        attributeSlots = inlineAttributes[];
        parameterSlots = inlineParameters[];
    }

    protected override void clear() nothrow
    {
        inlineFields[] = null;
        inlineAttributes[] = Attribute.init;
        if (attributeBlock.length > 14)
            attributeBlock = null;
        else
            attributeBlock[] = Attribute.init;
        inlineParameters[] = Parameter.init;
        method = requestURI = queryString = protocol = servletPath = contextPath = null;
        names = values = null;
        content = null;
        requestNumber = 0;
        dispatcherType = DispatcherType.REQUEST;
        parametersParsed = inputUsed = false;
        attributeSlots = inlineAttributes[];
        attributeCount = 0;
        parameterSlots = inlineParameters[];
        parameterCount = 0;
        parameterIndex = null;
        characterEncoding = null;
    }
}

// The façade is a handle in the 64-byte size class; the storage is pooled (coordination/notes/exchange-pool.md).
static assert(__traits(classInstanceSize, ServletEngineRequest) <= 64);
