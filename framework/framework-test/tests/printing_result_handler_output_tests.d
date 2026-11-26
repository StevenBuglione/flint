module printing_result_handler_output_tests;

import flint.mock.web : MockHttpServletRequest, MockHttpServletResponse;
import flint.test.web.servlet : DefaultMvcResult;
import flint.test.web.servlet.result : MockMvcResultHandlers;

@safe:

private enum report = "\n" ~ `MockHttpServletRequest:
      HTTP Method = POST
      Request URI = /report
       Parameters = {item=[one, two]}
          Headers = [X-Trace:"a", "b"]
             Body = request
    Session Attrs = {}

Handler:
             Type = null

Resolved Exception:
             Type = null

MockHttpServletResponse:
           Status = 299
    Error message = null
          Headers = []
     Content type = null
` ~ "             Body = réponse\0tail\n" ~ `    Forwarded URL = null
   Redirected URL = null
          Cookies = []
`;

private DefaultMvcResult sampleResult()
{
    auto request = new MockHttpServletRequest("POST", "/report");
    request.addParameter("item", "one", "two");
    request.addHeader("X-Trace", "a");
    request.addHeader("X-Trace", "b");
    request.setContent(cast(const(ubyte)[]) "request");

    auto response = new MockHttpServletResponse;
    response.setStatus(299);
    response.setCharacterEncoding("UTF-8");
    response.getOutputStream().write(cast(const(ubyte)[]) "réponse\0tail");
    return new DefaultMvcResult(request, response);
}

@("MockMvc log keeps the complete report and updates it on each result")
unittest
{
    import std.array : replace;

    auto result = sampleResult();
    auto logger = MockMvcResultHandlers.log();
    assert(logger.getText() is null);
    logger.handle(result);
    assert(logger.getText() == report, logger.getText());
    result.getResponse().setStatus(int.min);
    logger.handle(result);
    assert(logger.getText() == report.replace("299", "-2147483648"), logger.getText());
}

version (Posix)
{
    import core.stdc.stdio : BUFSIZ, clearerr, fflush, stdout;
    import core.sys.posix.unistd : STDOUT_FILENO, close, dup, dup2;
    import std.stdio : File;

    private void withStandardOutput(File target, scope void delegate() @safe exercise) @system
    {
        const saved = dup(STDOUT_FILENO);
        assert(saved >= 0);
        scope (exit)
        {
            fflush(stdout);
            dup2(saved, STDOUT_FILENO);
            close(saved);
            clearerr(stdout);
        }
        const flushed = fflush(stdout);
        assert(flushed == 0);
        const changed = dup2(target.fileno(), STDOUT_FILENO);
        assert(changed == STDOUT_FILENO);
        exercise();
    }

    @("MockMvc print writes the complete report once and log leaves standard output alone")
    @system unittest
    {
        auto captured = File.tmpfile();
        withStandardOutput(captured, () {
            auto result = sampleResult();
            MockMvcResultHandlers.log().handle(result);
            MockMvcResultHandlers.print().handle(result);
            const flushed = fflush(stdout);
            assert(flushed == 0);
        });

        captured.rewind();
        char[report.length + 1] buffer;
        assert(captured.rawRead(buffer[]) == report);
    }

    @("MockMvc print reports a failed standard output write as an IOException")
    @system unittest
    {
        import flint.java.io : IOException;

        withStandardOutput(File("/dev/null", "r"), () {
            auto result = sampleResult();
            result.getResponse().getOutputStream().write(new ubyte[2 * BUFSIZ]);
            try
            {
                MockMvcResultHandlers.print().handle(result);
                assert(false, "expected the write to fail");
            }
            catch (IOException failure)
            {
                assert(failure.getMessage() == "Could not write MockMvc result to standard output");
            }
        });
    }
}
