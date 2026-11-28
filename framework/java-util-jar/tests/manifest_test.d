// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0

module manifest_test;

import flint.engine.aot.any : Any;
import flint.java.io : ByteArrayInputStream, ByteArrayOutputStream, IOException;
import std.exception : assertThrown;
import flint.java.lang : ClassCastException, IllegalArgumentException, NullPointerException;
import flint.java.util.jar : Attributes, Manifest, Name;

@safe:

private ubyte[] utf8(string text)
{
    return cast(ubyte[]) text.dup;
}

private string repeat(char c, size_t count)
{
    auto result = new char[count];
    result[] = c;
    return result.idup;
}

private string repeatString(string text, size_t count)
{
    string result;
    foreach (_; 0 .. count)
        result ~= text;
    return result;
}

private string asString(ubyte[] bytes) @trusted
{
    return cast(string) bytes;
}

@("Attributes.Name constants, case-insensitive equality and hash")
unittest
{
    assert(Attributes.Name.MANIFEST_VERSION.toString() == "Manifest-Version");
    assert(Attributes.Name.SIGNATURE_VERSION.toString() == "Signature-Version");
    assert(Attributes.Name.CONTENT_TYPE.toString() == "Content-Type");
    assert(Attributes.Name.CLASS_PATH.toString() == "Class-Path");
    assert(Attributes.Name.MAIN_CLASS.toString() == "Main-Class");
    assert(Attributes.Name.SEALED.toString() == "Sealed");
    assert(Attributes.Name.EXTENSION_LIST.toString() == "Extension-List");
    assert(Attributes.Name.EXTENSION_NAME.toString() == "Extension-Name");
    assert(Attributes.Name.EXTENSION_INSTALLATION.toString() == "Extension-Installation");
    assert(Attributes.Name.IMPLEMENTATION_TITLE.toString() == "Implementation-Title");
    assert(Attributes.Name.IMPLEMENTATION_VERSION.toString() == "Implementation-Version");
    assert(Attributes.Name.IMPLEMENTATION_VENDOR.toString() == "Implementation-Vendor");
    assert(Attributes.Name.IMPLEMENTATION_VENDOR_ID.toString() == "Implementation-Vendor-Id");
    assert(Attributes.Name.IMPLEMENTATION_URL.toString() == "Implementation-URL");
    assert(Attributes.Name.SPECIFICATION_TITLE.toString() == "Specification-Title");
    assert(Attributes.Name.SPECIFICATION_VERSION.toString() == "Specification-Version");
    assert(Attributes.Name.SPECIFICATION_VENDOR.toString() == "Specification-Vendor");
    assert(Attributes.Name.MULTI_RELEASE.toString() == "Multi-Release");

    const lower = new Attributes.Name("main-class");
    const upper = new Attributes.Name("MAIN-CLASS");
    assert(lower.equals(upper));
    assert(lower.toString() == "main-class");
    assert(lower.hashCode() == Attributes.Name.MAIN_CLASS.hashCode());
    assert(!lower.equals(cast(Object) null));
}

@("Attributes.Name validates Java's grammar")
unittest
{
    assertThrown!NullPointerException(new Attributes.Name(null));
    foreach (bad; ["", "a" ~ repeat('a', 70), "Bad Name", "Bad:Name", "Bad.Name", "caf\u00e9"])
        assertThrown!IllegalArgumentException(new Attributes.Name(bad));

    const len70 = "A0_-" ~ repeat('z', 66);
    assert(new Attributes.Name(len70).toString() == len70);
}

@("Attributes preserves insertion order and replaces names case-insensitively")
unittest
{
    auto attrs = new Attributes();
    assert(attrs.putValue("Created-By", "Flint") is null);
    assert(attrs.putValue("Main-Class", "demo.App") is null);
    assert(attrs.getValue("created-by") == "Flint");
    assert(attrs.getValue(Attributes.Name.MAIN_CLASS) == "demo.App");
    assert(attrs.putValue("CREATED-BY", "Flint2") == "Flint");

    auto names = attrs.keySet();
    assert(names.length == 2);
    string[] seen;
    foreach (name; names)
        seen ~= name.toString();
    assert(seen == ["Created-By", "Main-Class"]);

    assertThrown!ClassCastException(attrs.put(Any.of("Not-A-Name"), Any.of("v")));
    assertThrown!ClassCastException(attrs.put(Any.of(new Attributes.Name("Sealed")), Any.of(123)));
    assertThrown!ClassCastException(attrs.putAll(null));

    auto cloned = cast(Attributes) attrs.clone();
    cloned.putValue("Sealed", "true");
    assert(attrs.getValue("Sealed") is null);
}

@("Manifest write omits main attributes without a version, then round-trips")
unittest
{
    auto noVer = new Manifest();
    noVer.getMainAttributes().putValue("Main-Class", "demo.App");
    auto entry = new Attributes();
    entry.putValue("Content-Type", "text/plain");
    noVer.getEntries().put("a.txt", entry);

    auto bytes = new ByteArrayOutputStream();
    noVer.write(bytes);
    assert(bytes.toString() == "\r\nName: a.txt\r\nContent-Type: text/plain\r\n\r\n");

    auto manifest = new Manifest();
    auto longUtf8 = repeatString("\u20ac", 30);
    manifest.getMainAttributes().putValue("Custom-Utf8", longUtf8);
    manifest.getMainAttributes().putValue("Manifest-Version", "1.0");
    auto digest = new Attributes();
    digest.putValue("Digest", repeat('x', 70));
    const longName = "pkg/" ~ repeatString("segment/", 12) ~ "File.class";
    manifest.getEntries().put(longName, digest);

    bytes.reset();
    manifest.write(bytes);
    auto written = bytes.toByteArray();
    assert(asString(written[0 .. 21]) == "Manifest-Version: 1.0");

    size_t lineStart;
    foreach (i; 0 .. written.length)
    {
        if (i + 1 < written.length && written[i] == '\r' && written[i + 1] == '\n')
        {
            assert(i - lineStart <= 72);
            lineStart = i + 1 + 1;
        }
    }

    auto parsed = new Manifest(new ByteArrayInputStream(written));
    assert(parsed.equals(manifest));
    assert(parsed.getMainAttributes().getValue("Custom-Utf8") == longUtf8);
    assert(parsed.getAttributes(longName) !is null);
    assert(parsed.hashCode() == manifest.hashCode());
}

@("Manifest read accepts CR, LF and CRLF, wraps names, and merges")
unittest
{
    const mixed = "Manifest-Version: 1.0\nCreated-By: one\r\r\n\nnAmE: foo/\r bar.txt\rAttr-A: val1\n val2\r\n\r\n";
    auto manifest = new Manifest();
    manifest.getMainAttributes().putValue("Pre-Existing", "keep");
    manifest.read(new ByteArrayInputStream(utf8(mixed)));
    assert(manifest.getMainAttributes().getValue("Pre-Existing") == "keep");
    assert(manifest.getMainAttributes().getValue("Manifest-Version") == "1.0");
    assert(manifest.getMainAttributes().getValue("Created-By") == "one");
    assert(manifest.getAttributes("foo/bar.txt").getValue("Attr-A") == "val1val2");
}

@("Manifest read rejects malformed sections")
unittest
{
    foreach (bad; [
        " leading-space\r\n", "MissingSpace:value\r\n", "NoColonLine\r\n",
        "Manifest-Version: 1.0\r\n\r\nNotName: foo\r\n", "Bad Name: value\r\n",
        "Manifest-Version: " ~ repeat('a', 520) ~ "\r\n"
    ])
    {
        auto manifest = new Manifest();
        bool threw;
        try
            manifest.read(new ByteArrayInputStream(utf8(bad)));
        catch (IOException)
            threw = true;
        assert(threw, bad);
    }
}
