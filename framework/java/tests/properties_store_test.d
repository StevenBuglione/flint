module properties_store_test;

import flint.java.io : ByteArrayInputStream, ByteArrayOutputStream, OutputStream, StringWriter, Writer;
import flint.java.lang : NullPointerException, System;
import flint.java.util : Properties;
import std.exception : assertThrown;
import std.string : indexOf;

@safe:

@("Properties store round-trips keys and values, escaping the format's syntax characters") unittest
{
    auto source = new Properties;
    source.setProperty("plain", "value");
    source.setProperty("space key", " leading");
    source.setProperty("sep=key:colon", "a=b:c#d!e");
    source.setProperty("controls", "\t\n\r\f\\");
    source.setProperty("unicode", "caf\u00e9 \U0001f600");
    source.setProperty("empty", "");

    auto writer = new StringWriter();
    source.store(writer, null);
    auto text = writer.toString();
    const separator = System.lineSeparator();
    assert(containsText(text, "plain=value" ~ separator));
    assert(containsText(text, "space\\ key=\\ leading" ~ separator));
    assert(containsText(text, "sep\\=key\\:colon=a\\=b\\:c\\#d\\!e" ~ separator));
    assert(containsText(text, "controls=\\t\\n\\r\\f\\\\" ~ separator));
    assert(containsText(text, "unicode=caf\\u00E9 \\uD83D\\uDE00" ~ separator));
    assert(containsText(text, "empty=" ~ separator));

    auto loaded = new Properties;
    loaded.load(text);
    foreach (key; source.keySet().toArray())
        assert(loaded.getProperty(key) == source.getProperty(key));
    assert(loaded.size() == source.size());
}

@("Properties store writes a date comment, keeps existing comment markers, and escapes non-Latin-1") unittest
{
    auto properties = new Properties;
    properties.setProperty("a", "1");
    auto writer = new StringWriter();
    properties.store(writer, "first\n#already\n!bang\ncaf\u00e9 \U0001f600");
    auto lines = splitLines(writer.toString());
    assert(lines.length == 6);
    assert(lines[0] == "#first");
    assert(lines[1] == "#already");
    assert(lines[2] == "!bang");
    assert(lines[3] == "#caf\u00e9 \\uD83D\\uDE00");
    assert(lines[4].length > 0 && lines[4][0] == '#' && containsText(lines[4], " UTC "));
    assert(lines[5] == "a=1");
}

@("Properties store writes only its own entries, not the defaults") unittest
{
    auto defaults = new Properties;
    defaults.setProperty("inherited", "yes");
    auto properties = new Properties(defaults);
    properties.setProperty("own", "1");
    auto writer = new StringWriter();
    properties.store(writer, null);
    auto text = writer.toString();
    assert(!containsText(text, "inherited"));
    assert(containsText(text, "own=1"));
}

@("Properties store(OutputStream) writes ISO-8859-1 bytes and leaves the stream open") unittest
{
    auto properties = new Properties;
    properties.setProperty("key", "caf\u00e9");
    auto output = new ByteArrayOutputStream();
    properties.store(output, "comment \u00e9");
    auto bytes = output.toByteArray();
    bool sawLatin1;
    bool sawUtf8;
    foreach (index, octet; bytes)
    {
        if (octet == 0xe9)
            sawLatin1 = true;
        if (octet == 0xc3 && index + 1 < bytes.length && bytes[index + 1] == 0xa9)
            sawUtf8 = true;
    }
    assert(sawLatin1 && !sawUtf8);

    auto loaded = new Properties;
    loaded.load(new ByteArrayInputStream(bytes));
    assert(loaded.getProperty("key") == "caf\u00e9");
}

@("Properties store rejects a null writer or stream") unittest
{
    auto properties = new Properties;
    assertThrown!NullPointerException(properties.store(cast(Writer) null, null));
    assertThrown!NullPointerException(properties.store(cast(OutputStream) null, null));
}

private bool containsText(string text, string part)
{
    return text.indexOf(part) >= 0;
}

private string[] splitLines(string text)
{
    string[] lines;
    const separator = System.lineSeparator();
    size_t start;
    while (start < text.length)
    {
        const end = text[start .. $].indexOf(separator);
        if (end < 0)
        {
            lines ~= text[start .. $];
            break;
        }
        lines ~= text[start .. start + end];
        start += end + separator.length;
    }
    return lines;
}
