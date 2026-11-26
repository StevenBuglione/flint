/++
Flint checks of the mock request's and response's numeric and text header handling, which reads and writes numbers
through engine-aot's text helpers rather than Phobos: Spring's `MockHttpServletRequest.getIntHeader` and the
response's `Content-Length` setter parse as `Integer.parseInt`/`Long.parseLong` do and throw
`NumberFormatException`; `Accept-Language` skips an entry with a malformed weight; a charset parameter is found in any
case.
+/
module mock_servlet_header_text_tests;

import flint.java.lang : NumberFormatException;
import flint.mock.web : MockHttpServletRequest, MockHttpServletResponse;

@safe:

@("Mock request reads only the first date header value")
unittest
{
    auto request = new MockHttpServletRequest;
    assert(request.getDateHeader("If-Modified-Since") == -1);
    request.addHeader("If-Modified-Since", "Tue, 21 Jul 2015 10:00:00 GMT");
    request.addHeader("if-modified-since", "not a date");
    assert(request.getDateHeader("If-Modified-Since") == 1_437_472_800_000);
}

@("MockHttpServletRequest.getIntHeader parses a signed int, is -1 when absent, and rejects malformed or wide values")
unittest
{
    auto request = new MockHttpServletRequest();
    assert(request.getIntHeader("X-Count") == -1);
    request.addHeader("X-Count", "-42");
    assert(request.getIntHeader("X-Count") == -42);
    request.addHeader("X-Plus", "+7");
    assert(request.getIntHeader("X-Plus") == 7);
    foreach (bad; ["4 2", "", "0x10", "2147483648"])
    {
        auto other = new MockHttpServletRequest();
        other.addHeader("X-Count", bad);
        bool thrown;
        try
            other.getIntHeader("X-Count");
        catch (NumberFormatException)
            thrown = true;
        assert(thrown, bad);
    }
}

@("MockHttpServletRequest.getRequestURL prints a non-default port and omits a default one")
unittest
{
    auto request = new MockHttpServletRequest("GET", "/path");
    request.setServerName("example.org");
    request.setServerPort(8443);
    assert(request.getRequestURL() == "http://example.org:8443/path");
    request.setServerPort(80);
    assert(request.getRequestURL() == "http://example.org/path");
}

@("MockHttpServletRequest: an Accept-Language entry with a malformed weight is skipped, and spaces are trimmed")
unittest
{
    auto request = new MockHttpServletRequest();
    request.addHeader("Accept-Language", " de ;q=abc,  fr ; q=0.5 ,\ten;q=0.8\t");
    const locales = request.getLocales();
    assert(locales.length == 2);
    assert(locales[0].toLanguageTag() == "en");
    assert(locales[1].toLanguageTag() == "fr");
}

@("MockHttpServletResponse: Content-Length and int headers print in decimal; a malformed length throws")
unittest
{
    auto response = new MockHttpServletResponse();
    response.setHeader("Content-Length", "1234567890123");
    assert(response.getContentLengthLong() == 1_234_567_890_123);
    assert(response.getHeader("Content-Length") == "1234567890123");
    response.setIntHeader("X-Count", -5);
    response.addIntHeader("X-Count", 6);
    assert(response.getHeaders("X-Count") == ["-5", "6"]);
    bool thrown;
    try
        response.setHeader("Content-Length", "12a");
    catch (NumberFormatException)
        thrown = true;
    assert(thrown);
    assert(response.getContentLengthLong() == 1_234_567_890_123);
}

@("MockHttpServletResponse: a charset parameter in any case is kept as written, not appended again")
unittest
{
    auto response = new MockHttpServletResponse();
    response.setCharacterEncoding("UTF-8");
    response.setContentType("text/plain; CHARSET=ISO-8859-1");
    assert(response.getHeader("Content-Type") == "text/plain; CHARSET=ISO-8859-1");
    response.setContentType("text/html");
    assert(response.getHeader("Content-Type") == "text/html;charset=ISO-8859-1");
}
