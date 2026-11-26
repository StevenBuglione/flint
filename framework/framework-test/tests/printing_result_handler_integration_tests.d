/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/test/web/servlet/samples/standalone/resulthandlers/
PrintingResultHandlerIntegrationTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: set the ISO-8859-1 converter and UTF-8 response encodings explicitly.
+/
module printing_result_handler_integration_tests;

import flint.http : MediaType;
import flint.http.converter : StringHttpMessageConverter;
import flint.jakarta.servlet.http : Cookie, HttpServletResponse;
import flint.java.io : ByteArrayOutputStream, IOException, StringWriter, Writer;
import flint.java.lang : AssertionError;
import flint.java.nio.charset : StandardCharsets;
import flint.test.web.servlet.request : MockMvcRequestBuilders;
import flint.test.web.servlet.result : MockMvcResultHandlers, MockMvcResultMatchers;
import flint.test.web.servlet.setup : MockMvcBuilders;
import flint.web.bind.annotation : GetMapping, RestController;
import std.algorithm.searching : canFind;

@safe:

private alias get = MockMvcRequestBuilders.get;
private alias print = MockMvcResultHandlers.print;
private alias content = MockMvcResultMatchers.content;

@RestController
private final class SimpleController
{
    @GetMapping("/")
    string hello(HttpServletResponse response)
    {
        response.addCookie(new Cookie("enigma", "42"));
        return "Hello Response";
    }

    @GetMapping("/utf8")
    string utf8(HttpServletResponse response)
    {
        response.setCharacterEncoding("UTF-8");
        return "Grüß dich!";
    }
}

private auto latin1Builder()
{
    return MockMvcBuilders.standaloneSetup(new SimpleController)
        .setMessageConverters(new StringHttpMessageConverter(StandardCharsets.ISO_8859_1));
}

private auto helloRequest()
{
    return get("/").content("Hello Request").characterEncoding(StandardCharsets.ISO_8859_1);
}

private void assertHelloReport(string report)
{
    assert(report.canFind("Hello Request"), report);
    assert(report.canFind("Hello Response"), report);
    assert(report.canFind(
            `Headers = [Set-Cookie:"enigma=42", Content-Type:"text/plain;charset=ISO-8859-1", Content-Length:"14"]`),
            report);
}

@("printMvcResultsToWriter")
unittest
{
    auto writer = new StringWriter;
    latin1Builder().alwaysDo(print(writer)).build().perform(helloRequest()).andExpect(content()
            .string("Hello Response"));
    assertHelloReport(writer.toString());
}

@("printMvcResultsToWriterWithJsonResponseBodyInterpretedAsUtf8")
unittest
{
    auto writer = new StringWriter;
    MockMvcBuilders.standaloneSetup(new SimpleController).build().perform(get("/utf8")
            .accept(MediaType.APPLICATION_JSON).content("Hallöchen, Welt!").characterEncoding(StandardCharsets.UTF_8))
        .andDo(print(writer)).andExpect(content().bytes(cast(const(ubyte)[]) "Grüß dich!"));
    const report = writer.toString();
    assert(report.canFind("Body = Hallöchen, Welt!"), report);
    assert(report.canFind("Body = Grüß dich!"), report);
}

@("printMvcResultsToWriterWithFailingGlobalResultMatcher")
unittest
{
    auto writer = new StringWriter;
    try
    {
        latin1Builder().alwaysDo(print(writer)).alwaysExpect(content().string("Boom!")).build().perform(helloRequest());
        assert(false, "expected the global result matcher to fail");
    }
    catch (AssertionError failure)
        assert(failure.getMessage().canFind("Boom!"), failure.getMessage());
    assertHelloReport(writer.toString());
}

private final class FlushedByteStream : ByteArrayOutputStream
{
    bool flushed;

    override void flush()
    {
        flushed = true;
    }
}

@("Printing to an OutputStream writes UTF-8 and flushes the supplied stream")
unittest
{
    auto stream = new FlushedByteStream;
    MockMvcBuilders.standaloneSetup(new SimpleController).alwaysDo(print(stream)).build()
        .perform(get("/utf8").accept(MediaType.APPLICATION_JSON));
    assert(stream.toString().canFind("Body = Grüß dich!"), stream.toString());
    assert(stream.flushed);
}

private final class FailingWriter : Writer
{
    bool attempted;

    override void write(scope const(char)[])
    {
        attempted = true;
        throw new IOException("closed sink");
    }
}

@("A writer IOException leaves the MockMvc result available")
unittest
{
    auto writer = new FailingWriter;
    latin1Builder().alwaysDo(print(writer)).build().perform(helloRequest()).andExpect(content()
            .string("Hello Response"));
    assert(writer.attempted);
}
