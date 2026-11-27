module flint.java.charset_gaps_test;

import flint.java.lang : stringHashCode;
import flint.java.nio.charset : Charset, IllegalCharsetNameException, StandardCharsets, UnsupportedCharsetException;

@safe:

@("forName and isSupported follow Java's checkName rules")
unittest
{
    assert(Charset.forName("UTF-8") == StandardCharsets.UTF_8);
    assert(Charset.forName("utf-8") == StandardCharsets.UTF_8);
    assert(Charset.forName("unicode-1-1-utf-8") == StandardCharsets.UTF_8);

    // An empty name is illegal, as in Java.
    try
    {
        Charset.forName("");
        assert(false, "Expected forName(\"\") to throw IllegalCharsetNameException");
    }
    catch (IllegalCharsetNameException)
    {
    }

    // A name with a space is illegal, as in Java's checkName.
    try
    {
        Charset.forName("a b");
        assert(false, "Expected forName(\"a b\") to throw IllegalCharsetNameException");
    }
    catch (IllegalCharsetNameException)
    {
    }

    // A legal but unknown name is unsupported, as in Java.
    try
    {
        Charset.forName("bogus");
        assert(false, "Expected forName(\"bogus\") to throw UnsupportedCharsetException");
    }
    catch (UnsupportedCharsetException)
    {
    }

    assert(Charset.isSupported("UTF-8"));
    assert(Charset.isSupported("utf-8"));
    assert(!Charset.isSupported("bogus"));

    try
    {
        Charset.isSupported("");
        assert(false, "Expected isSupported(\"\") to throw IllegalCharsetNameException");
    }
    catch (IllegalCharsetNameException)
    {
    }

    try
    {
        Charset.isSupported("a b");
        assert(false, "Expected isSupported(\"a b\") to throw IllegalCharsetNameException");
    }
    catch (IllegalCharsetNameException)
    {
    }
}

@("forName with a fallback returns the fallback for illegal or unknown names")
unittest
{
    assert(Charset.forName("UTF-8", StandardCharsets.US_ASCII) == StandardCharsets.UTF_8);
    assert(Charset.forName("a b", StandardCharsets.US_ASCII) == StandardCharsets.US_ASCII);
    assert(Charset.forName("bogus", StandardCharsets.US_ASCII) == StandardCharsets.US_ASCII);
    assert(Charset.forName("", StandardCharsets.US_ASCII) == StandardCharsets.US_ASCII);
}

@("hashCode, equals, canEncode, isRegistered and defaultCharset match Java's")
unittest
{
    foreach (charset; [
        StandardCharsets.UTF_8, StandardCharsets.US_ASCII, StandardCharsets.ISO_8859_1,
        StandardCharsets.UTF_16, StandardCharsets.UTF_16BE, StandardCharsets.UTF_16LE
    ])
    {
        assert(charset.hashCode() == stringHashCode(charset.name()));
        assert(charset == charset);
        assert(charset.canEncode());
        assert(charset.isRegistered());
    }

    assert(StandardCharsets.UTF_8 != StandardCharsets.US_ASCII);
    assert(Charset.defaultCharset() == StandardCharsets.UTF_8);
}

@("contains follows the standard containment table")
unittest
{
    // Every charset contains itself.
    foreach (charset; [
        StandardCharsets.UTF_8, StandardCharsets.US_ASCII, StandardCharsets.ISO_8859_1,
        StandardCharsets.UTF_16, StandardCharsets.UTF_16BE, StandardCharsets.UTF_16LE
    ])
        assert(charset.contains(charset));

    // US-ASCII contains only itself; ISO-8859-1 contains US-ASCII and itself.
    assert(StandardCharsets.US_ASCII.contains(StandardCharsets.ISO_8859_1) == false);
    assert(StandardCharsets.ISO_8859_1.contains(StandardCharsets.US_ASCII));
    assert(StandardCharsets.ISO_8859_1.contains(StandardCharsets.ISO_8859_1));
    assert(StandardCharsets.ISO_8859_1.contains(StandardCharsets.UTF_8) == false);

    // The UTF charsets contain all six.
    foreach (charset; [
        StandardCharsets.UTF_8, StandardCharsets.UTF_16, StandardCharsets.UTF_16BE,
        StandardCharsets.UTF_16LE
    ])
    {
        assert(charset.contains(StandardCharsets.US_ASCII));
        assert(charset.contains(StandardCharsets.ISO_8859_1));
        assert(charset.contains(StandardCharsets.UTF_8));
        assert(charset.contains(StandardCharsets.UTF_16));
        assert(charset.contains(StandardCharsets.UTF_16BE));
        assert(charset.contains(StandardCharsets.UTF_16LE));
    }
}
