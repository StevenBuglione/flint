module flint.java.net.formoverloads_test;

import flint.java.io.unsupportedencodingexception : UnsupportedEncodingException;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.net.urldecoder : URLDecoder;
import flint.java.net.urlencoder : URLEncoder;
import flint.java.nio.charset : Charset, StandardCharsets;

@safe:

@("form overloads support both charset values and Java charset aliases")
unittest
{
    assert(URLEncoder.encode("café", "UTF8") == "caf%C3%A9");
    assert(URLEncoder.encode("café", StandardCharsets.ISO_8859_1) == "caf%E9");
    assert(URLDecoder.decode("caf%C3%A9", "UTF8") == "café");
    assert(URLDecoder.decode("caf%E9", StandardCharsets.ISO_8859_1) == "café");
    assert(URLDecoder.decode("", StandardCharsets.UTF_8) == "");
    assert(URLEncoder.encode("", StandardCharsets.UTF_8) == "");
}

@("form named overloads report unsupported or illegal charset names before visiting input")
unittest
{
    foreach (name; ["", "not-a-real-charset", "a!"])
    {
        try
        {
            cast(void) URLEncoder.encode("café", name);
            assert(false, "invalid charset accepted");
        }
        catch (UnsupportedEncodingException failure)
        {
            assert(failure.getMessage() == name && failure.getMessage() !is null);
        }
        try
        {
            cast(void) URLDecoder.decode("a%ZZ", name);
            assert(false, "invalid charset accepted");
        }
        catch (UnsupportedEncodingException failure)
        {
            assert(failure.getMessage() == (name.length == 0 ? "URLDecoder: empty string enc parameter" : name));
        }
    }

    try
    {
        cast(void) URLEncoder.encode("", Charset.init);
        assert(false, "null charset accepted");
    }
    catch (NullPointerException failure)
    {
        assert(failure.msg == "charset");
    }
    try
    {
        cast(void) URLDecoder.decode("", Charset.init);
        assert(false, "null charset accepted");
    }
    catch (NullPointerException failure)
    {
        assert(failure.msg == "Charset");
    }
}

@("URLDecoder distinguishes incomplete, negative and invalid hexadecimal escapes")
unittest
{
    enum badHex = "URLDecoder: Illegal hex characters in escape (%) pattern - ";
    auto messages = [
        "%é": "URLDecoder: Incomplete trailing escape (%) pattern",
        "%-1": badHex ~ "negative value", "x%41%GZ": badHex ~ "Error at index 0 in: \"GZ\"",
        "%-G": badHex ~ "Error at index 1 in: \"-G\"",
        "%𝟘X": badHex ~ "Error at index 0 in: \"𝟘\"",
        "%A𝟘": badHex ~ "Error at index 1 in: \"A?\"",
    ];
    foreach (input, message; messages)
    {
        try
        {
            cast(void) URLDecoder.decode(input, StandardCharsets.UTF_8);
            assert(false, "invalid form escape accepted");
        }
        catch (IllegalArgumentException failure)
        {
            assert(failure.msg == message, failure.msg);
        }
    }
}
