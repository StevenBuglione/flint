/++
Flint tests of `UriComponents`' port as text: `getPort` reads it as `Integer.parseInt` does and reports anything else
with Spring's `IllegalStateException`, and `UriComponentsBuilder.port(int)` prints it in decimal. Both go through
engine-aot's text helpers rather than `std.conv`.
+/
module flint.web.util.uri_port_text_tests;

import flint.java.lang : IllegalStateException;
import flint.web.util : UriComponentsBuilder;

@safe:

@("UriComponents.getPort reads a decimal int and rejects other text with Spring's message")
unittest
{
    assert(UriComponentsBuilder.fromUriString("https://example.com/bar").port("+8080").build().getPort() == 8080);
    foreach (bad; ["XXX", "80a", "2147483648", "-"])
    {
        auto uri = UriComponentsBuilder.fromUriString("https://example.com/bar").port(bad).build();
        try
        {
            uri.getPort();
            assert(false, bad);
        }
        catch (IllegalStateException e)
            assert(e.msg == "The port must be an integer: " ~ bad, e.msg);
    }
}

@("UriComponentsBuilder.port(int) prints the port in decimal and a negative port clears it")
unittest
{
    auto builder = UriComponentsBuilder.fromUriString("https://example.com/bar");
    assert(builder.port(65_535).build().toUriString() == "https://example.com:65535/bar");
    assert(builder.port(-1).build().toUriString() == "https://example.com/bar");
}
