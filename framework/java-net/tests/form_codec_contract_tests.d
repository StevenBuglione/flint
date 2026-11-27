/// Original Flint tests for the Java SE form codec contract.
module flint.java.net.form_codec_contract_tests;

import flint.java.io.unsupportedencodingexception : UnsupportedEncodingException;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.net.urldecoder : URLDecoder;
import flint.java.net.urlencoder : URLEncoder;
import flint.java.nio.charset : Charset, StandardCharsets;
import std.exception : assertThrown, collectException;

@safe:

@("form overloads treat null input as empty")
unittest
{
    const string absent = null;
    assert(URLEncoder.encode(absent) == URLEncoder.encode(""));
    assert(URLDecoder.decode(absent) == URLDecoder.decode(""));
    assert(URLEncoder.encode(absent, "UTF-8") == URLEncoder.encode("", "UTF-8"));
    assert(URLDecoder.decode(absent, "UTF-8") == URLDecoder.decode("", "UTF-8"));
    assert(URLEncoder.encode(absent, StandardCharsets.UTF_8) == "");
    assert(URLDecoder.decode(absent, StandardCharsets.UTF_8) == "");
}

@("charset selection applies before an empty input is returned")
unittest
{
    const string absent = null;
    auto encodeCharset = collectException!NullPointerException(URLEncoder.encode(absent, Charset.init));
    auto decodeCharset = collectException!NullPointerException(URLDecoder.decode(absent, Charset.init));
    assert(encodeCharset !is null && encodeCharset.msg == "charset");
    assert(decodeCharset !is null && decodeCharset.msg == "Charset");
    assertThrown!UnsupportedEncodingException(URLEncoder.encode(absent, "not-a-real-charset"));
    assertThrown!UnsupportedEncodingException(URLDecoder.decode(absent, "not-a-real-charset"));
}

@("a null charset name is handled as empty")
unittest
{
    foreach (name; [cast(string) null, ""])
    {
        auto encodeError = collectException!UnsupportedEncodingException(URLEncoder.encode("name=value", name));
        auto decodeError = collectException!UnsupportedEncodingException(URLDecoder.decode("name%3Dvalue", name));
        assert(encodeError !is null && encodeError.msg == "");
        assert(decodeError !is null && decodeError.msg == "URLDecoder: empty string enc parameter");
    }
}

@("URL decoding validates escapes and keeps ordinary input verbatim")
unittest
{
    foreach (input; ["draft%", "lead%4", "contact%4Q", "x%20%f", "%-9"])
    {
        assertThrown!IllegalArgumentException(URLDecoder.decode(input, "UTF-8"));
        assertThrown!IllegalArgumentException(URLDecoder.decode(input, StandardCharsets.UTF_8));
    }
    assertThrown!IllegalArgumentException(URLDecoder.decode("%-a", "ISO-8859-1"));
    assert(URLDecoder.decode("file name@example#section", "UTF-8") == "file name@example#section");
}

@("UTF-16 form encoding crosses neither spaces nor ASCII boundaries")
unittest
{
    const utf16 = StandardCharsets.UTF_16;
    foreach (input; ["γ δ", "a☃☂ z", "code & note", "𝄞+♩", "one two három"])
    {
        const encoded = URLEncoder.encode(input, utf16);
        assert(encoded == URLEncoder.encode(input, "UTF-16"));
        assert(URLDecoder.decode(encoded, utf16) == input);
    }
}

@("the form codec escapes ASCII punctuation and supplementary code points")
unittest
{
    const input = "item +%._-*~&é🛰";
    const encoded = "item+%2B%25._-*%7E%26%C3%A9%F0%9F%9B%B0";
    assert(URLEncoder.encode(input, "UTF-8") == encoded);
    assert(URLDecoder.decode(encoded, "UTF-8") == input);

    assert(URLEncoder.encode("\U00010000", "UTF-8") == "%F0%90%80%80");
    assert(URLEncoder.encode("\U0010FFFF", "UTF-8") == "%F4%8F%BF%BF");
    assert(URLDecoder.decode("%F0%90%80%80%F4%8F%BF%BF", "UTF-8") == "\U00010000\U0010FFFF");
}

@("the name and Charset overloads agree across Unicode byte lengths")
unittest
{
    const utf8 = StandardCharsets.UTF_8;
    foreach (range; [[0, 128], [128, 256]])
    {
        char[] text;
        foreach (codePoint; range[0] .. range[1])
            text ~= cast(dchar) codePoint;
        const input = text.idup;
        const encoded = URLEncoder.encode(input, "UTF-8");
        assert(encoded == URLEncoder.encode(input, utf8));
        assert(URLDecoder.decode(encoded, "UTF-8") == input);
        assert(URLDecoder.decode(encoded, utf8) == input);
    }
    foreach (input; ["", "n", "x y+z-*", "Ζητήστε", "字々", "🔎"])
    {
        const encoded = URLEncoder.encode(input, utf8);
        assert(encoded == URLEncoder.encode(input, "UTF-8"));
        assert(URLDecoder.decode(encoded, "UTF-8") == input);
        assert(URLDecoder.decode(encoded, utf8) == input);
    }
}
