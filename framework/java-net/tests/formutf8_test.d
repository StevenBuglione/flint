module flint.java.net.formutf8_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.net.internal.formencode : encodeFormUtf8;
import flint.java.net.internal.formutf8 : decodeFormUtf8;

@safe:

@("form encoding escapes UTF-8 octets and leaves the Java ASCII safe set unchanged")
unittest
{
    enum plain = "AZaz09.-_*";
    assert(encodeFormUtf8(plain) is plain);
    assert(encodeFormUtf8(" +~%/") == "+%2B%7E%25%2F");
    assert(encodeFormUtf8("café 😀") == "caf%C3%A9+%F0%9F%98%80");
    assert(decodeFormUtf8("caf%C3%A9+%F0%9F%98%80") == "café 😀");
    assert(decodeFormUtf8("%2B+%00") == "+ \0");
}

@("form decoding follows Java hexadecimal syntax and rejects incomplete escapes")
unittest
{
    assert(decodeFormUtf8("%+A%４１%٤١%-0%+Ａ") == "\nAA\0\n");
    foreach (text; ["%", "a%F", "%G0", "% 2", "%-1", "%𝟘"])
    {
        try
        {
            cast(void) decodeFormUtf8(text);
            assert(false, "invalid escape accepted");
        }
        catch (IllegalArgumentException)
        {
        }
    }
}

@("malformed percent-decoded UTF-8 replaces the invalid prefix and keeps the following byte")
unittest
{
    assert(decodeFormUtf8("%E2%82%41") == "�A");
    assert(decodeFormUtf8("%E0%80%AF%41") == "���A");
    assert(decodeFormUtf8("%ED%A0%80%41") == "�A");
    assert(decodeFormUtf8("%C3x%A9") == "�x�");
}
