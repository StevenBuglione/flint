// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.jar.jarentry_test;

import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.util.jar.jarentry : JarEntry;
import flint.java.util.zip.zipentry : ZipEntry;
import std.exception : assertThrown;

@safe:

@("the name constructor keeps its name and rejects null or over-long names")
unittest
{
    auto entry = new JarEntry("dir/file.txt");
    assert(entry.getName() == "dir/file.txt");
    assert(entry.getRealName() == "dir/file.txt");

    assertThrown!NullPointerException(new JarEntry(cast(string) null));

    auto tooLong = new char[0x1_0000];
    assertThrown!IllegalArgumentException(new JarEntry(tooLong.idup));
}

@("the ZipEntry constructor copies the entry's fields")
unittest
{
    auto source = new ZipEntry("a/b");
    source.setMethod(ZipEntry.DEFLATED);
    source.setCrc(0x1234_5678);
    source.setSize(41);
    source.setCompressedSize(17);
    source.setComment("note");
    source.setExtra([cast(byte) 1, cast(byte) 2, cast(byte) 3]);

    auto entry = new JarEntry(source);
    assert(entry.getName() == "a/b");
    assert(entry.getRealName() == "a/b");
    assert(entry.getMethod() == ZipEntry.DEFLATED);
    assert(entry.getCrc() == 0x1234_5678);
    assert(entry.getSize() == 41);
    assert(entry.getCompressedSize() == 17);
    assert(entry.getComment() == "note");
    assert(entry.getExtra() == source.getExtra());
    assert(entry.getAttributes() is null);
}

@("the JarEntry copy constructor is a JarEntry and shares the manifest attributes")
unittest
{
    auto source = new JarEntry("a/b");
    source.setSize(7);
    auto copy = new JarEntry(source);
    assert(copy !is null);
    assert((cast(ZipEntry) copy) !is null);
    assert(copy.getName() == "a/b");
    assert(copy.getSize() == 7);
    assert(copy.getAttributes() is null);
}

@("a JarEntry with no manifest section has null attributes")
unittest
{
    auto entry = new JarEntry("plain");
    assert(entry.getAttributes() is null);
}
