/++
The servlet engine over real sockets, with a plain `HttpServlet`: Tomcat's framing, field order, error-page
forward, exception handling, parameters and keep-alive.
+/
module servlet_engine_tests;

import core.time : MonoTime, dur;
import flint.engine.aot.any : Any;
import flint.engine.servlet : ErrorPageShortcut, ServletEngine, ServletEngineException, ServletEngineOptions;
import flint.jakarta.servlet : DispatcherType, Filter, FilterChain, RequestDispatcher,
    ServletRequest, ServletResponse;
import flint.jakarta.servlet.http : HttpServlet, HttpServletRequest, HttpServletRequestWrapper, HttpServletResponse;
import flint.java.lang : IllegalStateException;
static import flint.java.lang;
import flint.java.util : Locale;
import std.socket : InternetAddress, Socket, SocketOption, SocketOptionLevel, TcpSocket;

@safe:

private final class Probe : HttpServlet
{
    long counter;

    protected override string[] getDeclaredMethods()
    {
        return ["GET", "POST"];
    }

    protected override void doGet(HttpServletRequest request, HttpServletResponse response)
    {
        if (request.getDispatcherType() == DispatcherType.ERROR)
            return errorPage(request, response);
        alias Page = void delegate(HttpServletRequest, HttpServletResponse) @safe;
        const Page[string] pages = [
            "/greeting": &greeting, "/committed": &committed, "/empty": &empty,
            "/fields": &fields, "/throw": &fail, "/lazy": &failLazily, "/headers": &headers,
            "/visit": &visit, "/large": &large, "/ranged": &ranged, "/many": &many,
            "/twelve": &twelve
        ];
        if (auto page = request.getServletPath() in pages)
            return (*page)(request, response);
        response.setHeader("Allow", "GET");
        response.sendError(request.getServletPath() == "/nope" ? 404 : 405);
    }

    private void greeting(HttpServletRequest request, HttpServletResponse response)
    {
        ++counter;
        string joined;
        foreach (index, value; request.getParameterValues("name"))
            joined ~= (index != 0 ? "," : "") ~ value;
        if (joined.length == 0)
            joined = "World";
        response.setContentType("application/json");
        response.getOutputStream()
            .write(cast(const(ubyte)[])(`{"id":` ~ decimal(counter) ~ `,"content":"Hello, ` ~ joined ~ `!"}`));
    }

    private void committed(HttpServletRequest, HttpServletResponse response)
    {
        response.setHeader("X-First", "1");
        response.setContentType("application/json");
        response.getOutputStream().write(cast(const(ubyte)[]) `{"committed":true}`);
        response.flushBuffer();
        response.setHeader("X-Late", "ignored");
    }

    private void ranged(HttpServletRequest, HttpServletResponse response)
    {
        response.setBufferSize(2);
        response.getOutputStream().write(cast(const(ubyte)[]) "_abcd_", 1, 4);
    }

    private void empty(HttpServletRequest, HttpServletResponse response)
    {
        response.setStatus(406);
        response.setHeader("Accept", "application/json, application/*+json");
    }

    private void fields(HttpServletRequest, HttpServletResponse response)
    {
        response.addHeader("Vary", "Origin");
        response.addHeader("Vary", "Access-Control-Request-Method");
        response.setHeader("X-Replaced", "a");
        response.setHeader("X-Replaced", "b");
        response.setContentType("text/html;charset=UTF-8");
        response.setLocale(Locale.US);
        response.getWriter().print("<p>é</p>");
    }

    private void fail(HttpServletRequest, HttpServletResponse)
    {
        throw new IllegalStateException("boom");
    }

    /// Throws an exception whose message exists only in `getMessage` (built on demand, `msg` empty).
    private void failLazily(HttpServletRequest, HttpServletResponse)
    {
        throw new MessageOnDemand;
    }

    private void headers(HttpServletRequest request, HttpServletResponse response)
    {
        response.setContentType("text/plain");
        response.getWriter()
            .print(request.getHeader("X-Trace") ~ "|" ~ request.getHeader(
                    "x-trace") ~ "|" ~ request.getServerName() ~ "|" ~ decimal(
                    request.getServerPort()) ~ "|" ~ request.getRequestURL() ~ "|" ~ request.getQueryString()
                    ~ "|" ~ request.getProtocol() ~ "|" ~ request.getLocale().toLanguageTag());
    }

    /// The header fields as the request hands them over in one pass (its HeaderFieldSource side).
    private void visit(HttpServletRequest request, HttpServletResponse response)
    {
        import flint.engine.servlet.request : ServletEngineRequest;

        string text;
        auto source = cast(ServletEngineRequest) request;
        if (source is null)
            text = "no source";
        else
            source.visitHeaderFields((string name, string value) { text ~= name ~ "=" ~ value ~ ";"; });
        response.setContentType("text/plain");
        response.getWriter().print(text);
    }

    /// More attributes, parameters and fields than the request and response hold inside themselves.
    private void many(HttpServletRequest request, HttpServletResponse response)
    {
        foreach (index; 0 .. 12)
            request.setAttribute("a" ~ decimal(index), Any.of(cast(int) index));
        request.setAttribute("a3", Any.of(30));
        request.removeAttribute("a5");
        string attributes;
        foreach (name; request.getAttributeNames())
            attributes ~= name ~ "=" ~ decimal(request.getAttribute(name).get!int) ~ " ";
        string parameters;
        foreach (name; request.getParameterNames())
        {
            parameters ~= name ~ "=";
            foreach (value; request.getParameterValues(name))
                parameters ~= value ~ ",";
        }
        foreach (index; 0 .. 10)
            response.addHeader("X-" ~ decimal(index), decimal(index));
        response.setHeader("X-2", "two"); // inside the response's slots, now on the heap
        response.setHeader("X-9", "nine");
        // Past the heap block's first growth, then a replacement that drops a repeat, then more fields.
        foreach (index; 10 .. 18)
            response.addHeader("X-" ~ decimal(index), decimal(index));
        response.addHeader("X-3", "again");
        response.setHeader("X-3", "three"); // keeps the first X-3's place, drops the repeat
        response.addHeader("X-18", "18");
        response.setContentType("text/plain");
        response.getWriter().print(attributes ~ "|" ~ parameters);
    }

    /// Twelve fields, past the inline slots and inside the block the state keeps: `tag` in each value, `drop` set
    /// replaces X-3 so the fields move to a fresh array before the twelfth.
    private void twelve(HttpServletRequest request, HttpServletResponse response)
    {
        const tag = request.getParameter("tag");
        foreach (index; 0 .. 11)
            response.addHeader("X-" ~ decimal(index), tag ~ decimal(index));
        if (request.getParameter("drop") !is null)
        {
            response.addHeader("X-3", "repeat");
            response.setHeader("X-3", tag ~ "-three");
        }
        response.addHeader("X-11", tag ~ "11");
        response.setContentType("text/plain");
        response.getWriter().print(tag);
    }

    private void large(HttpServletRequest, HttpServletResponse response)
    {
        response.setContentType("text/plain");
        auto writer = response.getWriter();
        foreach (_; 0 .. 1000)
            writer.print("0123456789");
    }

    protected override void doPost(HttpServletRequest request, HttpServletResponse response)
    {
        if (request.getDispatcherType() == DispatcherType.ERROR)
            return errorPage(request, response);
        if (request.getServletPath() == "/many")
            return many(request, response);
        response.setHeader("Allow", "GET");
        response.sendError(405, "Method 'POST' is not supported.");
    }

    /// Stands in for Boot's BasicErrorController: echoes the error attributes, then commits (chunked).
    private void errorPage(HttpServletRequest request, HttpServletResponse response)
    {
        const code = request.getAttribute(RequestDispatcher.ERROR_STATUS_CODE).get!int;
        const uri = request.getAttribute(RequestDispatcher.ERROR_REQUEST_URI).get!string;
        const message = request.getAttribute(RequestDispatcher.ERROR_MESSAGE).get!string;
        auto exception = request.getAttribute(RequestDispatcher.ERROR_EXCEPTION);
        response.setStatus(code);
        response.setContentType("application/json");
        response.getOutputStream()
            .write(cast(const(ubyte)[])(`{"status":` ~ decimal(
                    code) ~ `,"path":"` ~ uri ~ `","message":"` ~ message ~ `","exception":` ~ (exception.isNull()
                    ? "null" : `"` ~ request.getAttribute(RequestDispatcher.ERROR_EXCEPTION_TYPE).get!string ~ `"`)
                    ~ `,"at":"` ~ request.getRequestURI() ~ `"}`));
        response.flushBuffer();
    }
}

/// A Flint exception whose message is built on demand: `msg` stays empty and only `getMessage` has the text.
private final class MessageOnDemand : flint.java.lang.RuntimeException
{
    this() pure nothrow
    {
        super();
    }

    override string getMessage() const pure nothrow @nogc
    {
        return "on demand";
    }
}

private string decimal(long value)
{
    import std.conv : to;

    return value.to!string;
}

private struct Fixture
{
    ServletEngine engine;
    Probe probe;
    ushort port;

    void open(string contextPath = "")
    {
        ServletEngineOptions options;
        options.address = "127.0.0.1";
        options.contextPath = contextPath;
        options.port = 0;
        engine = new ServletEngine(options);
        probe = new Probe;
        engine.addServlet("dispatcherServlet", probe);
        engine.start();
        port = cast(ushort) engine.getPort();
        assert(port != 0);
    }

    void close()
    {
        engine.stop();
    }

    Socket connect()
    {
        auto socket = new TcpSocket(new InternetAddress("127.0.0.1", port));
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(3_000));
        return socket;
    }
}

private bool interrupted() @trusted
{
    import core.stdc.errno : EINTR, errno;

    return errno == EINTR;
}

private void sendAll(Socket socket, scope const(char)[] text)
{
    const(ubyte)[] bytes = cast(const(ubyte)[]) text;
    while (bytes.length != 0)
    {
        const sent = socket.send(bytes);
        if (sent == Socket.ERROR && interrupted())
            continue;
        assert(sent > 0);
        bytes = bytes[sent .. $];
    }
}

private ptrdiff_t find(scope const(char)[] text, scope const(char)[] needle, size_t from = 0)
{
    foreach (index; from .. text.length >= needle.length ? text.length - needle.length + 1 : from)
        if (text[index .. index + needle.length] == needle)
            return index;
    return -1;
}

/// One response, head and decoded content, read off a keep-alive connection.
private struct Exchange
{
    string head;
    string content;
    size_t dataChunks;

    /// The head without its Date line, which the suites do not compare either.
    string headWithoutDate() const
    {
        const at = find(head, "Date: ");
        if (at < 0)
            return head;
        const end = find(head, "\r\n", at);
        return head[0 .. at] ~ head[end + 2 .. $];
    }
}

private Exchange exchange(Socket socket, ref char[] received, scope const(char)[] request, bool head = false)
{
    sendAll(socket, request);
    char[4096] chunk;
    const deadline = MonoTime.currTime + dur!"seconds"(5);
    for (;;)
    {
        const end = find(received, "\r\n\r\n");
        if (end >= 0)
        {
            const headText = received[0 .. end + 4];
            const start = end + 4;
            const lengthAt = find(headText, "\r\nContent-Length: ");
            if (head)
            {
                auto result = Exchange(headText.idup, "");
                received = received[start .. $].dup;
                return result;
            }
            if (lengthAt >= 0)
            {
                size_t length;
                foreach (c; headText[lengthAt + 18 .. $])
                {
                    if (c < '0' || c > '9')
                        break;
                    length = length * 10 + (c - '0');
                }
                if (received.length >= start + length)
                {
                    auto result = Exchange(headText.idup, received[start .. start + length].idup);
                    received = received[start + length .. $].dup;
                    return result;
                }
            }
            else
            {
                const last = find(received, "\r\n0\r\n\r\n", start - 2);
                if (last >= 0)
                {
                    size_t dataChunks;
                    auto content = dechunk(received[start .. last + 7], dataChunks);
                    auto result = Exchange(headText.idup, content, dataChunks);
                    received = received[last + 7 .. $].dup;
                    return result;
                }
            }
        }
        assert(MonoTime.currTime < deadline, "timed out: " ~ received.idup);
        ptrdiff_t count;
        do
            count = socket.receive(chunk[]);
        while (count == Socket.ERROR && interrupted());
        assert(count > 0, "connection closed: " ~ received.idup);
        received ~= chunk[0 .. count];
    }
}

private string dechunk(scope const(char)[] text, out size_t dataChunks)
{
    string decoded;
    size_t at;
    for (;;)
    {
        size_t size;
        while (text[at] != '\r')
        {
            const c = text[at++];
            size = size * 16 + (c <= '9' ? c - '0' : c - 'a' + 10);
        }
        at += 2;
        if (size == 0)
            return decoded;
        ++dataChunks;
        decoded ~= text[at .. at + size];
        at += size + 2;
    }
}

@("an uncommitted response is sent whole with Content-Length and no reason phrase")
unittest
{
    Fixture fixture;
    fixture.open();
    scope (exit)
        fixture.close();
    auto socket = fixture.connect();
    scope (exit)
        socket.close();
    char[] pending;

    auto reply = exchange(socket, pending, "GET /greeting HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.headWithoutDate() == "HTTP/1.1 200 \r\nContent-Type: application/json\r\nContent-Length: 34\r\n\r\n",
            reply.head);
    assert(reply.content == `{"id":1,"content":"Hello, World!"}`, reply.content);

    // Query parameters: '+' is a space, UTF-8 percent bytes decode, repeated values join, empty is the default.
    reply = exchange(socket, pending, "GET /greeting?name=Jane+Q%20Public HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.content == `{"id":2,"content":"Hello, Jane Q Public!"}`, reply.content);
    reply = exchange(socket, pending, "GET /greeting?name=%C3%A9t%C3%A9 HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.content == `{"id":3,"content":"Hello, été!"}`, reply.content);
    reply = exchange(socket, pending, "GET /greeting?name=a&name=b HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.content == `{"id":4,"content":"Hello, a,b!"}`, reply.content);

    // An empty response that was never committed: Content-Length: 0 after the application's fields.
    reply = exchange(socket, pending, "GET /empty HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.headWithoutDate() == "HTTP/1.1 406 \r\nAccept: application/json, application/*+json\r\n"
            ~ "Content-Length: 0\r\n\r\n", reply.head);

    // HEAD: the handler runs, Content-Length is the length of the body that is not sent.
    reply = exchange(socket, pending, "HEAD /greeting HTTP/1.1\r\nHost: localhost\r\n\r\n", true);
    assert(reply.headWithoutDate() == "HTTP/1.1 200 \r\nContent-Type: application/json\r\nContent-Length: 34\r\n\r\n",
            reply.head);
    reply = exchange(socket, pending, "GET /greeting?name=again HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.content == `{"id":6,"content":"Hello, again!"}`, reply.content);

    // Past 16 names the parameters are indexed; values still join in arrival order.
    string query = "name=x";
    foreach (index; 0 .. 20)
        query ~= "&p" ~ decimal(index) ~ "=" ~ decimal(index);
    reply = exchange(socket, pending, "GET /greeting?" ~ query ~ "&name=y HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.content == `{"id":7,"content":"Hello, x,y!"}`, reply.content);
}

@("flushBuffer commits with chunked framing and freezes the fields; a full buffer commits too")
unittest
{
    Fixture fixture;
    fixture.open();
    scope (exit)
        fixture.close();
    auto socket = fixture.connect();
    scope (exit)
        socket.close();
    char[] pending;

    auto reply = exchange(socket, pending, "GET /committed HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.headWithoutDate() == "HTTP/1.1 200 \r\nX-First: 1\r\nContent-Type: application/json\r\n"
            ~ "Transfer-Encoding: chunked\r\n\r\n", reply.head);
    assert(reply.content == `{"committed":true}`, reply.content);

    // 10,000 bytes overflow Tomcat's 8 KiB buffer: committed early, so chunked.
    reply = exchange(socket, pending, "GET /large HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(find(reply.head, "Transfer-Encoding: chunked\r\n") > 0, reply.head);
    assert(reply.content.length == 10_000 && reply.content[0 .. 10] == "0123456789");
}

@("A ranged servlet output write that overflows the buffer sends one body chunk")
unittest
{
    Fixture fixture;
    fixture.open();
    scope (exit)
        fixture.close();
    auto socket = fixture.connect();
    scope (exit)
        socket.close();
    char[] pending;

    const reply = exchange(socket, pending, "GET /ranged HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.content == "abcd", reply.content);
    assert(reply.dataChunks == 1, "ranged output must send the whole selected slice in one chunk");
}

@("sendError forwards once to the error page with Tomcat's attributes, keeping fields set before it")
unittest
{
    Fixture fixture;
    fixture.open();
    scope (exit)
        fixture.close();
    auto socket = fixture.connect();
    scope (exit)
        socket.close();
    char[] pending;

    auto reply = exchange(socket, pending, "GET /nope HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.headWithoutDate() == "HTTP/1.1 404 \r\nAllow: GET\r\nContent-Type: application/json\r\n"
            ~ "Transfer-Encoding: chunked\r\n\r\n", reply.head);
    assert(reply.content == `{"status":404,"path":"/nope","message":"","exception":null,"at":"/error"}`, reply.content);

    reply = exchange(socket, pending, "POST /greeting HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n");
    assert(reply.head[0 .. 15] == "HTTP/1.1 405 \r\n", reply.head);
    assert(reply.content == `{"status":405,"path":"/greeting","message":"Method 'POST' is not supported.",`
            ~ `"exception":null,"at":"/error"}`, reply.content);

    // The connection is still in step after the error dispatches.
    reply = exchange(socket, pending, "GET /greeting HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.content == `{"id":1,"content":"Hello, World!"}`, reply.content);

    // An uncaught exception is a 500 forwarded with the exception's type. As in Tomcat
    // (Http11Processor.statusDropsConnection), a 500 closes the connection with "Connection: close".
    // The error page reads the message through getMessage(), as Tomcat's valve reads Throwable.getMessage();
    // on its own connection, since the 500 closes it.
    {
        auto lazySocket = fixture.connect();
        scope (exit)
            lazySocket.close();
        char[] lazyPending;
        const lazyReply = exchange(lazySocket, lazyPending, "GET /lazy HTTP/1.1\r\nHost: localhost\r\n\r\n");
        assert(lazyReply.content == `{"status":500,"path":"/lazy","message":"on demand",`
                ~ `"exception":"servlet_engine_tests.MessageOnDemand","at":"/error"}`, lazyReply.content);
    }

    reply = exchange(socket, pending, "GET /throw HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.head[0 .. 15] == "HTTP/1.1 500 \r\n", reply.head);
    assert(find(reply.head, "\r\nConnection: close\r\n") > 0, reply.head);
    assert(reply.content == `{"status":500,"path":"/throw","message":"boom",`
            ~ `"exception":"flint.java.lang.IllegalStateException","at":"/error"}`, reply.content);
    ubyte[1] rest;
    assert(socket.receive(rest[]) == 0, "the connection stays open after a 500");
}

@("a request outside the context path gets Tomcat's host-level 404 page; inside it, the servlet")
unittest
{
    Fixture fixture;
    fixture.open("/app");
    scope (exit)
        fixture.close();
    auto socket = fixture.connect();
    scope (exit)
        socket.close();
    char[] pending;

    auto reply = exchange(socket, pending, "GET /greeting HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.headWithoutDate() == "HTTP/1.1 404 \r\nContent-Type: text/html;charset=utf-8\r\n"
            ~ "Content-Language: en\r\nContent-Length: 431\r\n\r\n", reply.head);
    assert(reply.content[0 .. 67] == "<!doctype html><html lang=\"en\"><head><title>HTTP Status 404 \u2013 Not",
            reply.content);
    reply = exchange(socket, pending, "GET /application/greeting HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.head[0 .. 15] == "HTTP/1.1 404 \r\n", reply.head);
    assert(find(reply.content, "HTTP Status 404") > 0, reply.content);

    reply = exchange(socket, pending, "GET /app/greeting HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.content == `{"id":1,"content":"Hello, World!"}`, reply.content);
}

@("request fields, host, URL and query reach the servlet as copies; field order follows Tomcat")
unittest
{
    Fixture fixture;
    fixture.open();
    scope (exit)
        fixture.close();
    auto socket = fixture.connect();
    scope (exit)
        socket.close();
    char[] pending;

    auto reply = exchange(socket, pending, "GET /headers?a=1&b HTTP/1.1\r\nHost: example.test:8443\r\n"
            ~ "X-Trace: 7\r\nAccept-Language: de;q=0.5, fr-CH\r\n\r\n");
    assert(reply.content == "7|7|example.test|8443|http://example.test:8443/headers|a=1&b|HTTP/1.1|fr-CH",
            reply.content);

    // The request hands its fields over in arrival order with repeats kept, names lower-cased as it stores them.
    reply = exchange(socket, pending,
            "GET /visit HTTP/1.1\r\nHost: localhost\r\nX-A: 1\r\nAccept: */*\r\n" ~ "x-a: 2\r\n\r\n");
    assert(reply.content == "host=localhost;x-a=1;accept=*/*;x-a=2;", reply.content);

    // More fields than the request keeps inside itself (eight) arrive whole and in order.
    string many = "GET /visit HTTP/1.1\r\nHost: localhost\r\n";
    string expected = "host=localhost;";
    foreach (index; 0 .. 11)
    {
        many ~= "X-F" ~ decimal(index) ~ ": v" ~ decimal(index) ~ "\r\n";
        expected ~= "x-f" ~ decimal(index) ~ "=v" ~ decimal(index) ~ ";";
    }
    reply = exchange(socket, pending, many ~ "\r\n");
    assert(reply.content == expected, reply.content);

    // Repeated fields keep their order; a replaced field keeps its first position; Content-Type, then
    // Content-Language, follow the application's fields, as Tomcat writes them.
    reply = exchange(socket, pending, "GET /fields HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.headWithoutDate() == "HTTP/1.1 200 \r\nVary: Origin\r\nVary: Access-Control-Request-Method\r\n"
            ~ "X-Replaced: b\r\nContent-Type: text/html;charset=UTF-8\r\nContent-Language: en-US\r\n"
            ~ "Content-Length: 9\r\n\r\n", reply.head);
    assert(reply.content == "<p>é</p>", reply.content);

    // A request naming keep-alive gets Tomcat's Keep-Alive field with the 60 s timeout.
    reply = exchange(socket, pending, "GET /greeting HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n");
    assert(find(reply.head, "\r\nKeep-Alive: timeout=60\r\nConnection: keep-alive\r\n") > 0, reply.head);
}

@("attributes, parameters, fields and a form body past the inline slots keep their order and values")
unittest
{
    Fixture fixture;
    fixture.open();
    scope (exit)
        fixture.close();
    auto socket = fixture.connect();
    scope (exit)
        socket.close();
    char[] pending;

    // Parameters from the query and from a form body (copied with the request head, in one block).
    const form = "p4=4&p5=5&p1=1b&p6=%41";
    const formLength = decimal(form.length);
    auto reply = exchange(socket, pending, "POST /many?p1=1&p2=2&p3=3 HTTP/1.1\r\nHost: localhost\r\n"
            ~ "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: " ~ formLength ~ "\r\n\r\n" ~ form);
    assert(reply.content == "a0=0 a1=1 a2=2 a3=30 a4=4 a6=6 a7=7 a8=8 a9=9 a10=10 a11=11 "
            ~ "|p1=1,1b,p2=2,p3=3,p4=4,p5=5,p6=A,", reply.content);
    const contentLength = decimal(reply.content.length);
    assert(reply.headWithoutDate() == "HTTP/1.1 200 \r\nX-0: 0\r\nX-1: 1\r\nX-2: two\r\nX-3: three\r\n"
            ~ "X-4: 4\r\nX-5: 5\r\nX-6: 6\r\nX-7: 7\r\nX-8: 8\r\nX-9: nine\r\nX-10: 10\r\nX-11: 11\r\n"
            ~ "X-12: 12\r\nX-13: 13\r\nX-14: 14\r\nX-15: 15\r\nX-16: 16\r\nX-17: 17\r\nX-18: 18\r\n"
            ~ "Content-Type: text/plain;charset=ISO-8859-1\r\nContent-Length: " ~ contentLength ~ "\r\n\r\n",
            reply.head);

    // The next request on the connection starts from empty slots.
    reply = exchange(socket, pending, "GET /many?q=1 HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.content == "a0=0 a1=1 a2=2 a3=30 a4=4 a6=6 a7=7 a8=8 a9=9 a10=10 a11=11 |q=1,", reply.content);
}

@("a response reusing the header block an earlier exchange grew carries only its own fields")
unittest
{
    Fixture fixture;
    fixture.open();
    scope (exit)
        fixture.close();
    auto socket = fixture.connect();
    scope (exit)
        socket.close();
    char[] pending;

    // The same worker serves all three, so each reuses the block the first one grew.
    foreach (round; 0 .. 3)
    {
        const tag = ["a", "b", "c"][round], drop = round == 1 ? "&drop=1" : "";
        const reply = exchange(socket, pending,
                "GET /twelve?tag=" ~ tag ~ drop ~ " HTTP/1.1\r\nHost: localhost\r\n\r\n");
        string expected = "HTTP/1.1 200 \r\n";
        foreach (index; 0 .. 11)
        {
            const value = index == 3 && drop.length ? tag ~ "-three" : tag ~ decimal(index);
            expected ~= "X-" ~ decimal(index) ~ ": " ~ value ~ "\r\n";
        }
        expected ~= "X-11: " ~ tag ~ "11\r\nContent-Type: text/plain;charset=ISO-8859-1\r\nContent-Length: 1\r\n\r\n";
        assert(reply.headWithoutDate() == expected, reply.head);
        assert(reply.content == tag, reply.content);
    }
}

@("a second engine on a bound port fails to start with ServletEngineException")
unittest
{
    Fixture fixture;
    fixture.open();
    scope (exit)
        fixture.close();
    ServletEngineOptions options;
    options.address = "127.0.0.1";
    options.port = fixture.port;
    auto second = new ServletEngine(options);
    second.addServlet("dispatcherServlet", new Probe);
    bool failed;
    try
        second.start();
    catch (ServletEngineException e)
        failed = e.port == fixture.port;
    assert(failed);
    assert(second.getPort() == -1);
}

@("graceful shutdown with no requests in flight reports idle")
unittest
{
    Fixture fixture;
    fixture.open();
    assert(fixture.engine.shutDownGracefully(5_000_000_000L));
    fixture.engine.stop();
}

/// Adds a response field naming itself, then passes the request on.
private final class Tagging : Filter
{
    mixin Filter.Defaults;
    private string tag;

    this(string tag) pure nothrow @nogc
    {
        this.tag = tag;
    }

    void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
    {
        (cast(HttpServletResponse) response).addHeader("X-Filter", tag);
        chain.doFilter(request, response);
    }
}

@("a ServletContextInitializer registers the servlet and filters through ServletContext, as Boot's beans do")
unittest
{
    ServletEngineOptions options;
    options.address = "127.0.0.1";
    options.port = 0;
    auto engine = new ServletEngine(options);
    auto context = engine.getServletContext();
    auto servlet = context.addServlet("dispatcherServlet", new Probe);
    assert(servlet !is null && servlet.getName() == "dispatcherServlet");
    servlet.setLoadOnStartup(1);
    assert(servlet.addMapping("/").length == 0 && servlet.getMappings() == ["/"]);
    assert(context.addServlet("dispatcherServlet", new Probe) is null);
    // isMatchAfter true runs after every isMatchAfter false mapping, whatever the declaration order.
    context.addFilter("late", new Tagging("late")).addMappingForUrlPatterns(null, true, "/*");
    context.addFilter("early", new Tagging("early")).addMappingForUrlPatterns(null, false, "/*");
    context.addFilter("named", new Tagging("named")).addMappingForServletNames(null, false, "dispatcherServlet");
    context.addFilter("elsewhere", new Tagging("elsewhere")).addMappingForUrlPatterns(null, false, "/api/*");
    assert(context.addFilter("early", new Tagging("again")) is null);
    engine.start();
    scope (exit)
        engine.stop();
    bool refused;
    try
        context.addServlet("late", new Probe);
    catch (IllegalStateException)
        refused = true;
    assert(refused);

    auto socket = new TcpSocket(new InternetAddress("127.0.0.1", cast(ushort) engine.getPort()));
    socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(3_000));
    scope (exit)
        socket.close();
    char[] pending;
    auto reply = exchange(socket, pending, "GET /greeting HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.headWithoutDate() == "HTTP/1.1 200 \r\nX-Filter: early\r\nX-Filter: named\r\nX-Filter: late\r\n"
            ~ "Content-Type: application/json\r\nContent-Length: 34\r\n\r\n", reply.head);
}

/// A request with one header added, as Spring Security's wrappers add to the request they wrap.
private final class WrappedRequest : HttpServletRequestWrapper
{
    this(HttpServletRequest request)
    {
        super(request);
    }

    override string getHeader(string name)
    {
        return name == "X-Wrapped" ? "yes" : super.getHeader(name);
    }
}

/// Passes a `WrappedRequest` down the chain.
private final class Wrapping : Filter
{
    mixin Filter.Defaults;

    void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
    {
        chain.doFilter(new WrappedRequest(cast(HttpServletRequest) request), response);
    }
}

/// Forwards `/api/forward` to `/api/target`, which reports what it sees.
private final class Forwarding : HttpServlet
{
    protected override void doGet(HttpServletRequest request, HttpServletResponse response)
    {
        if (request.getServletPath() == "/api/forward")
            return request.getRequestDispatcher("/api/target").forward(request, response);
        response.setHeader("X-Seen", request.getHeader("X-Wrapped"));
        response.setHeader("X-Path", request.getServletPath());
        response.setContentType("text/plain");
        response.getWriter().write("ok");
    }
}

@("a request a filter wraps still selects the filters mapped to its path, and forwards through the engine")
unittest
{
    ServletEngineOptions options;
    options.address = "127.0.0.1";
    options.port = 0;
    auto engine = new ServletEngine(options);
    auto context = engine.getServletContext();
    context.addServlet("dispatcherServlet", new Forwarding).addMapping("/");
    context.addFilter("wrapping", new Wrapping).addMappingForUrlPatterns(null, false, "/*");
    context.addFilter("api", new Tagging("api")).addMappingForUrlPatterns(null, false, "/api/*");
    engine.start();
    scope (exit)
        engine.stop();

    auto socket = new TcpSocket(new InternetAddress("127.0.0.1", cast(ushort) engine.getPort()));
    socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(3_000));
    scope (exit)
        socket.close();
    char[] pending;
    auto reply = exchange(socket, pending, "GET /api/forward HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.headWithoutDate() == "HTTP/1.1 200 \r\nX-Filter: api\r\nX-Seen: yes\r\nX-Path: /api/target\r\n"
            ~ "Content-Type: text/plain;charset=ISO-8859-1\r\nContent-Length: 2\r\n\r\n", reply.head);
    assert(reply.content == "ok");
}

/// spring-petclinic-rest's updates: `new ResponseEntity<>(dto, HttpStatus.NO_CONTENT)`, a 204 with a JSON body.
private final class NoContentWithBody : HttpServlet
{
    protected override void doGet(HttpServletRequest request, HttpServletResponse response)
    {
        response.setStatus(204);
        response.setContentType("application/json");
        const json = `{"id":11,"firstName":"George"}`;
        response.setContentLength(cast(int) json.length);
        // Spring's ServletServerHttpResponse writes the body, then flushes it (commit by flushBuffer).
        response.getOutputStream().write(cast(const(ubyte)[]) json);
        response.flushBuffer();
    }
}

@("a 204 with a body sends Tomcat's head, Content-Type and no framing field, and no body")
unittest
{
    ServletEngineOptions options;
    options.address = "127.0.0.1";
    options.port = 0;
    auto engine = new ServletEngine(options);
    engine.getServletContext().addServlet("dispatcherServlet", new NoContentWithBody).addMapping("/");
    engine.start();
    scope (exit)
        engine.stop();

    auto socket = new TcpSocket(new InternetAddress("127.0.0.1", cast(ushort) engine.getPort()));
    socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(3_000));
    scope (exit)
        socket.close();
    char[] pending;
    auto reply = exchange(socket, pending, "GET /owners/11 HTTP/1.1\r\nHost: localhost\r\n\r\n", true);
    assert(reply.headWithoutDate() == "HTTP/1.1 204 \r\nContent-Type: application/json\r\n\r\n", reply.head);
    // The connection stays usable: the next response follows directly, with no stray body bytes before it.
    auto next = exchange(socket, pending, "GET /owners/11 HTTP/1.1\r\nHost: localhost\r\n\r\n", true);
    assert(next.headWithoutDate() == reply.headWithoutDate(), next.head);
}

/// Stands in for the shortcut Flint AOT installs: writes its own body for a 404 and refuses anything else.
private final class Shortcut : ErrorPageShortcut
{
    bool accept = true;
    Filter[] errorFilters;
    Filter[] requestFilters;
    uint written;
    uint refused;
    string seenUri;

    bool install(ServletEngine engine)
    {
        errorFilters = engine.filtersFor(DispatcherType.ERROR, "/error");
        requestFilters = engine.filtersFor(DispatcherType.REQUEST, "/nope");
        return accept;
    }

    bool writeErrorPage(HttpServletRequest request, HttpServletResponse response, int status, string page)
    {
        if (status != 404 || page != "/error")
        {
            ++refused;
            return false;
        }
        ++written;
        // The attributes are set before the shortcut runs, as before the ERROR dispatch.
        seenUri = request.getAttribute(RequestDispatcher.ERROR_REQUEST_URI).get!string;
        response.setContentType("application/json");
        response.getOutputStream().write(cast(const(ubyte)[]) `{"shortcut":404}`);
        response.flushBuffer();
        return true;
    }
}

private final class Counting : Filter
{
    mixin Filter.Defaults;
    uint calls;

    void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
    {
        ++calls;
        chain.doFilter(request, response);
    }
}

private ServletEngine openWith(Shortcut shortcut, Counting onError)
{
    ServletEngineOptions options;
    options.address = "127.0.0.1";
    options.port = 0;
    options.errorPageShortcut = shortcut;
    auto engine = new ServletEngine(options);
    engine.addServlet("dispatcherServlet", new Probe);
    if (onError !is null)
        engine.addFilter("onError", onError, ["/*"], [DispatcherType.ERROR]);
    engine.addFilter("onRequest", new Counting, ["/*"], [DispatcherType.REQUEST]);
    engine.start();
    return engine;
}

@("an installed error-page shortcut writes the 404 in place of the ERROR dispatch, and a refusal forwards")
unittest
{
    auto shortcut = new Shortcut;
    auto onError = new Counting;
    auto engine = openWith(shortcut, onError);
    const port = cast(ushort) engine.getPort();
    scope (exit)
        engine.stop();
    // The proof sees the filters a dispatch would run: only the ERROR-mapped one for the error page.
    assert(shortcut.errorFilters.length == 1 && shortcut.errorFilters[0] is onError);
    assert(shortcut.requestFilters.length == 1 && shortcut.requestFilters[0]!is onError);

    auto socket = new TcpSocket(new InternetAddress("127.0.0.1", port));
    socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(3_000));
    scope (exit)
        socket.close();
    char[] pending;
    auto reply = exchange(socket, pending, "GET /nope HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.headWithoutDate() == "HTTP/1.1 404 \r\nAllow: GET\r\nContent-Type: application/json\r\n"
            ~ "Transfer-Encoding: chunked\r\n\r\n", reply.head);
    assert(reply.content == `{"shortcut":404}`, reply.content);
    assert(shortcut.written == 1 && shortcut.seenUri == "/nope" && onError.calls == 0);

    // A 405 is refused: the generic forward runs the ERROR chain and the page.
    reply = exchange(socket, pending, "POST /greeting HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n");
    assert(reply.head[0 .. 15] == "HTTP/1.1 405 \r\n", reply.head);
    assert(reply.content == `{"status":405,"path":"/greeting","message":"Method 'POST' is not supported.",`
            ~ `"exception":null,"at":"/error"}`, reply.content);
    assert(shortcut.refused == 1 && onError.calls == 1);

    // The connection stays in step.
    reply = exchange(socket, pending, "GET /greeting HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.content == `{"id":1,"content":"Hello, World!"}`, reply.content);
}

@("a shortcut whose install declines is never called: every forward stays generic")
unittest
{
    auto shortcut = new Shortcut;
    shortcut.accept = false;
    auto engine = openWith(shortcut, null);
    const port = cast(ushort) engine.getPort();
    scope (exit)
        engine.stop();
    assert(shortcut.errorFilters.length == 0);
    auto socket = new TcpSocket(new InternetAddress("127.0.0.1", port));
    socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(3_000));
    scope (exit)
        socket.close();
    char[] pending;
    const reply = exchange(socket, pending, "GET /nope HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.content == `{"status":404,"path":"/nope","message":"","exception":null,"at":"/error"}`, reply.content);
    assert(shortcut.written == 0 && shortcut.refused == 0);
}

/// S5's engine side: a servlet whose fast path answers POST /fast from the offered body and declines the rest, which
/// the generic path then serves by reading the same body from the request's input stream.
private final class FastEcho : HttpServlet, imported!"flint.engine.aot.fast".FastDispatch
{
    import flint.engine.aot.fast : FastExchange, FastOutcome;

    size_t offers;
    string offeredBody;
    string offeredContentType;
    size_t offeredContentTypes;

    bool hasFastPath()
    {
        return true;
    }

    FastOutcome dispatchFast(ref scope FastExchange exchange)
    {
        ++offers;
        offeredBody = cast(string) exchange.requestBody.idup;
        offeredContentType = exchange.contentType.idup;
        offeredContentTypes = exchange.contentTypeCount;
        if (exchange.method != "POST" || exchange.path != "/fast")
            return FastOutcome.declined;
        exchange.respond(200, "text/plain", cast(const(ubyte)[])("fast:" ~ offeredBody));
        return FastOutcome.written;
    }

    protected override string[] getDeclaredMethods()
    {
        return ["GET", "POST"];
    }

    protected override void doGet(HttpServletRequest request, HttpServletResponse response)
    {
        response.setContentType("text/plain");
        response.getWriter().print("get");
    }

    protected override void doPost(HttpServletRequest request, HttpServletResponse response)
    {
        response.setContentType("text/plain");
        response.getWriter().print("generic:" ~ cast(string) request.getInputStream().readAllBytes().idup);
    }
}

@("S5: a POST is offered with its whole body; a declined one reads the same body; chunked and oversized ones are not offered")
unittest
{
    import flint.engine.servlet.fast : serveFast;

    ServletEngineOptions options;
    options.address = "127.0.0.1";
    options.port = 0;
    options.fastOffer = &serveFast;
    auto engine = new ServletEngine(options);
    auto echo = new FastEcho;
    engine.addServlet("dispatcherServlet", echo);
    engine.start();
    scope (exit)
        engine.stop();
    auto socket = new TcpSocket(new InternetAddress("127.0.0.1", cast(ushort) engine.getPort()));
    socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(3_000));
    scope (exit)
        socket.close();
    char[] pending;

    // Offered with the body, the Content-Type and its count; the fast path answers.
    auto reply = exchange(socket, pending, "POST /fast HTTP/1.1\r\nHost: localhost\r\n"
            ~ "Content-Type: application/json\r\nContent-Length: 7\r\n\r\n{\"a\":1}");
    assert(reply.content == `fast:{"a":1}`, reply.content);
    assert(echo.offers == 1 && echo.offeredBody == `{"a":1}`
            && echo.offeredContentType == "application/json" && echo.offeredContentTypes == 1);

    // Offered and declined: the generic path reads the same body from the input stream.
    reply = exchange(socket, pending, "POST /other HTTP/1.1\r\nHost: localhost\r\nContent-Type: text/plain\r\n"
            ~ "Content-Type: application/json\r\nContent-Length: 5\r\n\r\nhello");
    assert(reply.content == "generic:hello", reply.content);
    assert(echo.offers == 2 && echo.offeredBody == "hello" && echo.offeredContentType == "text/plain"
            && echo.offeredContentTypes == 2);

    // A POST without Content-Type, or with an empty body, is still offered.
    reply = exchange(socket, pending, "POST /fast HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n");
    assert(reply.content == "fast:", reply.content);
    assert(echo.offers == 3 && echo.offeredContentTypes == 0 && echo.offeredBody.length == 0);

    // Chunked: not offered, served generically with the dechunked body.
    reply = exchange(socket, pending,
            "POST /fast HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n" ~ "3\r\nabc\r\n0\r\n\r\n");
    assert(reply.content == "generic:abc", reply.content);
    assert(echo.offers == 3);

    // Larger than the fast path's stack copy (4 KiB): not offered.
    string large;
    foreach (_; 0 .. 4097)
        large ~= "x";
    reply = exchange(socket, pending, "POST /fast HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4097\r\n\r\n" ~ large);
    assert(reply.content == "generic:" ~ large);
    assert(echo.offers == 3);

    // A GET is still offered, with no body.
    reply = exchange(socket, pending, "GET /fast HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert(reply.content == "get", reply.content);
    assert(echo.offers == 4 && echo.offeredBody.length == 0);
}

/// What request A of the exchange-pool test keeps after its exchange, to use while later exchanges reuse its storage.
private struct Stash
{
    HttpServletResponse response;
    imported!"flint.jakarta.servlet".ServletOutputStream stream;
    string[] headerNames;
    string[] headerValues;
    HttpServletRequest request;
    imported!"flint.jakarta.servlet".ServletInputStream input;
    string[] attributeNames;
    string[] requestHeaders;
}

private __gshared Stash stash;
// The foreign thread of the race test (m7 A2): its attempts and how it ended.
private __gshared imported!"core.thread".Thread racer;
private shared int racerAttempts;
private __gshared string racerResult;

/// "ise;" when `action` throws `IllegalStateException`, "ok;" when it returns.
private string outcome(Action)(scope Action action) @trusted
{
    try
        action();
    catch (IllegalStateException)
        return "ise;";
    return "ok;";
}

/// Every retained object of A, used from the calling thread: "ise;" or "ok;" per use.
private string fromThisThread() @trusted
{
    string seen;
    seen ~= outcome(() { stash.response.getStatus(); });
    seen ~= outcome(() { stash.response.setHeader("X-Injected", "from-thread"); });
    seen ~= outcome(() { stash.response.addHeader("X-Injected", "from-thread"); });
    seen ~= outcome(() { stash.stream.write(cast(const(ubyte)[]) "injected"); });
    seen ~= outcome(() { stash.response.flushBuffer(); });
    seen ~= outcome(() { stash.response.getHeader("X-Secret"); });
    seen ~= outcome(() { stash.request.getAttribute("secret"); });
    seen ~= outcome(() { stash.request.setAttribute("injected", Any.of("from-thread")); });
    seen ~= outcome(() { stash.request.getAttributeNames(); });
    seen ~= outcome(() { stash.request.getHeader("X-Client"); });
    seen ~= outcome(() { stash.request.getRequestURI(); });
    seen ~= outcome(() { stash.input.readAllBytes(); });
    return seen;
}

/// A servlet for the exchange pool's adversarial test (coordination/notes/exchange-pool.md, test 1).
private final class Leaky : HttpServlet
{
    string fromFiber; // what the same worker saw when it touched A's objects during B

    protected override string[] getDeclaredMethods()
    {
        return ["GET"];
    }

    protected override void doGet(HttpServletRequest request, HttpServletResponse response) @trusted
    {
        const path = request.getServletPath();
        if (path == "/error" || path == "/plain")
            response.getOutputStream().write(cast(const(ubyte)[])(path == "/error" ? "error-page" : "plain"));
        else if (path == "/race")
            race(response);
        else if (path == "/fail")
            fail(request, response);
        else if (path == "/a")
            keep(request, response);
        else
            later(request, response, path);
    }

    // Another thread uses this response while the handler returns: off the worker, its flushes fail at once (the
    // transport is the worker's), so the return never waits on it for long, and once the exchange has completed it
    // gets IllegalStateException.
    private void race(HttpServletResponse response) @trusted
    {
        import core.atomic : atomicLoad, atomicOp;
        import core.thread : Thread;

        racer = new Thread({
            for (;;)
            {
                try
                {
                    response.setHeader("X-Race", "racer");
                    response.flushBuffer();
                }
                catch (IllegalStateException)
                {
                    racerResult = "ise";
                    return;
                }
                catch (Exception)
                {
                }
                atomicOp!"+="(racerAttempts, 1);
            }
        });
        racer.start();
        while (atomicLoad(racerAttempts) < 3)
            Thread.yield();
        response.getOutputStream().write(cast(const(ubyte)[]) "race");
    }

    // An exchange that ends in an exception, with its objects retained.
    private void fail(HttpServletRequest request, HttpServletResponse response) @trusted
    {
        stash.request = request;
        stash.response = response;
        stash.input = request.getInputStream();
        request.setAttribute("failing", Any.of("yes"));
        response.setHeader("X-Failing", "yes");
        throw new Exception("fail");
    }

    // A: retain every object the exchange hands out.
    private void keep(HttpServletRequest request, HttpServletResponse response) @trusted
    {
        response.setHeader("X-Secret", "alpha");
        response.addHeader("X-Trace", "a-1");
        stash.response = response;
        stash.stream = response.getOutputStream();
        stash.headerNames = response.getHeaderNames();
        stash.headerValues = response.getHeaders("X-Secret");
        request.setAttribute("secret", Any.of("alpha"));
        stash.request = request;
        stash.input = request.getInputStream();
        stash.attributeNames = request.getAttributeNames();
        stash.requestHeaders = request.getHeaders("X-Client");
        stash.stream.write(cast(const(ubyte)[]) "A-body");
    }

    // B, C, ...: different fields and bodies on the storage A's exchange used. Touching A's objects from this fiber,
    // on the same worker, must throw.
    private void later(HttpServletRequest request, HttpServletResponse response, string path) @trusted
    {
        response.setHeader("X-Secret", "beta-" ~ path[1 .. $]);
        auto output = response.getOutputStream();
        output.write(cast(const(ubyte)[])("B-body-" ~ path[1 .. $]));
        string seen;
        seen ~= outcome(() { stash.response.getStatus(); });
        seen ~= outcome(() { stash.response.setHeader("X-Injected", "from-a"); });
        seen ~= outcome(() { stash.stream.write(cast(const(ubyte)[]) "injected"); });
        seen ~= outcome(() { stash.response.getHeaderNames(); });
        seen ~= outcome(() { stash.request.getAttribute("secret"); });
        seen ~= outcome(() { stash.request.setAttribute("injected", Any.of("from-a")); });
        seen ~= outcome(() { stash.request.getHeader("X-Client"); });
        seen ~= outcome(() { stash.input.read(); });
        fromFiber = seen;
        // This exchange's own attributes and fields: nothing of A's, nothing injected.
        string attributes;
        foreach (name; request.getAttributeNames())
            attributes ~= name ~ ",";
        output.write(cast(const(ubyte)[])("|" ~ attributes ~ "|" ~ request.getHeader("X-Client")));
    }
}

@("exchange pool: retained request and response objects throw after their exchange, on its worker and off it, "
        ~ "and never touch a later exchange")
@trusted unittest
{
    ServletEngineOptions options;
    options.address = "127.0.0.1";
    options.port = 0;
    options.cores = 1; // one worker: every exchange reuses the same pooled storage
    auto engine = new ServletEngine(options);
    auto leaky = new Leaky;
    engine.addServlet("dispatcherServlet", leaky);
    engine.start();
    scope (exit)
        engine.stop();
    auto socket = new TcpSocket(new InternetAddress("127.0.0.1", cast(ushort) engine.getPort()));
    socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(3_000));
    scope (exit)
        socket.close();
    char[] pending;

    auto reply = exchange(socket, pending, "GET /a HTTP/1.1\r\nHost: localhost\r\nX-Client: alpha-client\r\n\r\n");
    assert(reply.content == "A-body", reply.content);
    assert(find(reply.head, "X-Secret: alpha") > 0);

    // B reuses A's storage; from B's fiber every use of A's objects throws, and B's own response is whole.
    reply = exchange(socket, pending, "GET /b HTTP/1.1\r\nHost: localhost\r\nX-Client: beta-client\r\n\r\n");
    assert(reply.content == "B-body-b||beta-client", reply.content);
    assert(find(reply.head, "X-Secret: beta-b") > 0 && find(reply.head, "X-Injected") < 0
            && find(reply.head, "alpha") < 0, reply.head);
    assert(leaky.fromFiber == "ise;ise;ise;ise;ise;ise;ise;ise;", leaky.fromFiber);

    // From this thread (not the worker): every use throws too.
    const seen = fromThisThread();
    assert(seen == "ise;ise;ise;ise;ise;ise;ise;ise;ise;ise;ise;ise;",
            "a retained object worked after its exchange: " ~ seen);
    // What A obtained during its exchange keeps A's values: fresh arrays, not views of the pooled storage.
    assert(stash.headerNames == ["X-Secret", "X-Trace"] && stash.headerValues == ["alpha"]);
    assert(stash.attributeNames == ["secret"] && stash.requestHeaders == ["alpha-client"]);

    // And C sees nothing anyone did to A's objects.
    reply = exchange(socket, pending, "GET /c HTTP/1.1\r\nHost: localhost\r\nX-Client: gamma-client\r\n\r\n");
    assert(reply.content == "B-body-c||gamma-client" && find(reply.head, "X-Injected") < 0
            && find(reply.head, "alpha") < 0, reply.head ~ reply.content);

    // An exchange that ends in an exception (a 500 through the error page, which closes its connection): its
    // retained objects stop working too, and the next exchange on the worker sees none of its state.
    auto failing = new TcpSocket(new InternetAddress("127.0.0.1", cast(ushort) engine.getPort()));
    failing.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(3_000));
    char[] failingPending;
    reply = exchange(failing, failingPending,
            "GET /fail HTTP/1.1\r\nHost: localhost\r\nX-Client: fail-client\r\n\r\n");
    failing.close();
    assert(reply.head[0 .. 15] == "HTTP/1.1 500 \r\n" && reply.content == "error-page", reply.head ~ reply.content);
    string afterFailure;
    afterFailure ~= outcome(() { stash.request.getAttribute("failing"); });
    afterFailure ~= outcome(() { stash.request.setAttribute("injected", Any.of("after-failure")); });
    afterFailure ~= outcome(() { stash.response.setHeader("X-Injected", "after-failure"); });
    afterFailure ~= outcome(() { stash.input.read(); });
    assert(afterFailure == "ise;ise;ise;ise;", "a retained object of a failed exchange worked: " ~ afterFailure);
    reply = exchange(socket, pending, "GET /d HTTP/1.1\r\nHost: localhost\r\nX-Client: delta-client\r\n\r\n");
    assert(reply.content == "B-body-d||delta-client" && find(reply.head, "X-Failing") < 0
            && find(reply.head, "X-Injected") < 0, reply.head ~ reply.content);
    assert(leaky.fromFiber == "ise;ise;ise;ise;ise;ise;ise;ise;", leaky.fromFiber);
}

@("exchange pool: another thread using a response while its handler returns neither hangs the worker nor "
        ~ "reaches the next exchange")
@trusted unittest
{
    import core.atomic : atomicLoad, atomicStore;

    ServletEngineOptions options;
    options.address = "127.0.0.1";
    options.port = 0;
    options.cores = 1;
    auto engine = new ServletEngine(options);
    engine.addServlet("dispatcherServlet", new Leaky);
    engine.start();
    scope (exit)
        engine.stop();
    auto socket = new TcpSocket(new InternetAddress("127.0.0.1", cast(ushort) engine.getPort()));
    socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(3_000));
    scope (exit)
        socket.close();
    char[] pending;
    foreach (round; 0 .. 20)
    {
        racer = null;
        racerResult = null;
        atomicStore(racerAttempts, 0);
        auto reply = exchange(socket, pending, "GET /race HTTP/1.1\r\nHost: localhost\r\n\r\n");
        assert(reply.head[0 .. 15] == "HTTP/1.1 200 \r\n" && reply.content == "race", reply.head ~ reply.content);
        racer.join();
        assert(racerResult == "ise" && atomicLoad(racerAttempts) >= 3, racerResult);
        reply = exchange(socket, pending, "GET /plain HTTP/1.1\r\nHost: localhost\r\n\r\n");
        assert(reply.content == "plain" && find(reply.head, "X-Race") < 0, reply.head ~ reply.content);
    }
}
