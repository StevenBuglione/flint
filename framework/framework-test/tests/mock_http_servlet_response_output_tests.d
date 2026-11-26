/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/mock/web/MockHttpServletResponseTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: use D bytes and strings for servlet output.
+/
module mock_http_servlet_response_output_tests;

import flint.jakarta.servlet.http : Cookie;
import flint.java.lang : IllegalStateException;
import flint.java.util : Locale;
import flint.mock.web : MockHttpServletResponse;

@safe:

@("servletOutputStreamCommittedWhenBufferSizeExceeded")
unittest
{
    auto response = new MockHttpServletResponse;
    auto output = response.getOutputStream();
    assert(!response.isCommitted());
    output.write('X');
    assert(!response.isCommitted());
    const size = response.getBufferSize();
    output.write(new ubyte[size]);
    assert(response.isCommitted());
    assert(response.getContentAsByteArray().length == size + 1);
}

@("servletOutputStreamCommittedOnFlushBuffer")
unittest
{
    auto response = new MockHttpServletResponse;
    assert(!response.isCommitted());
    response.getOutputStream().write('X');
    assert(!response.isCommitted());
    response.flushBuffer();
    assert(response.isCommitted());
    assert(response.getContentAsByteArray().length == 1);
}

@("servletWriterCommittedWhenBufferSizeExceeded")
unittest
{
    auto response = new MockHttpServletResponse;
    auto writer = response.getWriter();
    assert(!response.isCommitted());
    writer.write("X");
    assert(!response.isCommitted());
    const size = response.getBufferSize();
    auto text = new char[size];
    text[] = 'p';
    writer.write(text);
    assert(response.isCommitted());
    assert(response.getContentAsByteArray().length == size + 1);
}

@("servletOutputStreamCommittedOnOutputStreamFlush")
unittest
{
    auto response = new MockHttpServletResponse;
    auto output = response.getOutputStream();
    assert(!response.isCommitted());
    output.write('X');
    assert(!response.isCommitted());
    output.flush();
    assert(response.isCommitted());
    assert(response.getContentAsByteArray().length == 1);
}

@("servletWriterCommittedOnWriterFlush")
unittest
{
    auto response = new MockHttpServletResponse;
    auto writer = response.getWriter();
    assert(!response.isCommitted());
    writer.write("X");
    assert(!response.isCommitted());
    writer.flush();
    assert(response.isCommitted());
    assert(response.getContentAsByteArray().length == 1);
}

@("servletWriterCommittedOnWriterClose")
unittest
{
    auto response = new MockHttpServletResponse;
    auto writer = response.getWriter();
    assert(!response.isCommitted());
    writer.write("X");
    assert(!response.isCommitted());
    writer.close();
    assert(response.isCommitted());
    assert(response.getContentAsByteArray().length == 1);
    writer.write("ignored");
    assert(response.getContentAsByteArray().length == 1);
}

@("writerShouldFailWhenOutputStreamCalled")
unittest
{
    auto response = new MockHttpServletResponse;
    response.getOutputStream();
    try
    {
        response.getWriter();
        assert(false, "expected the stream to prevent writer access");
    }
    catch (IllegalStateException failure)
        assert(failure.getMessage() == "getOutputStream() has already been called");
}

@("outputStreamShouldFailWhenWriterCalled")
unittest
{
    auto response = new MockHttpServletResponse;
    response.getWriter();
    try
    {
        response.getOutputStream();
        assert(false, "expected the writer to prevent stream access");
    }
    catch (IllegalStateException failure)
        assert(failure.getMessage() == "getWriter() has already been called");
}

@("A configured positive buffer limit commits only after the size is exceeded")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setBufferSize(2);
    assert(response.getBufferSize() == 2);
    auto output = response.getOutputStream();
    output.write(cast(const(ubyte)[]) "ab");
    assert(!response.isCommitted());
    output.write('c');
    assert(response.isCommitted());
    try
    {
        response.resetBuffer();
        assert(false, "a committed body cannot be reset");
    }
    catch (IllegalStateException)
        assert(response.getContentAsString() == "abc");
}

@("A non-positive buffer size disables automatic commitment")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setBufferSize(0);
    auto writer = response.getWriter();
    writer.write("abc");
    assert(!response.isCommitted());
    writer.flush();
    assert(response.isCommitted());
}

@("Reset discards the body, headers and output selection and restores response defaults")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setBufferSize(32);
    response.setDefaultCharacterEncoding("UTF-8");
    response.setCharacterEncoding("ISO-8859-1");
    response.setContentLength(2);
    response.setContentType("text/plain");
    response.setLocale(Locale.FRANCE);
    response.setStatus(201);
    response.addCookie(new Cookie("id", "1"));
    auto writer = response.getWriter();
    assert(response.getWriter() is writer);
    writer.write("XY");

    response.resetBuffer();
    assert(response.getContentAsByteArray().length == 0);
    assert(response.getWriter() is writer);
    response.reset();

    assert(response.getBufferSize() == 32);
    assert(response.getContentAsByteArray().length == 0);
    assert(response.getContentLengthLong() == 0);
    assert(response.getContentType() is null);
    assert(response.getCharacterEncoding() == "UTF-8");
    assert(!response.isCharset());
    assert(response.getLocale() == Locale.getDefault());
    assert(response.getStatus() == 200);
    assert(response.getCookies().length == 0);
    assert(response.getHeaderNames().length == 0);
    auto output = response.getOutputStream();
    assert(response.getOutputStream() is output);
    output.write('Y');

    response.reset();
    assert(response.getWriter() !is writer);
    assert(response.getContentAsByteArray().length == 0);
}
