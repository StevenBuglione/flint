// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.zip.zipentry_test;

import flint.java.lang : IllegalArgumentException, NullPointerException, stringHashCode;
import flint.java.nio.file.attribute.filetime : FileTime;
import flint.java.time : Instant, LocalDateTime;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.zip.zipentry : ZipEntry;
import std.exception : assertThrown;

@safe:

private void put16(byte[] b, size_t off, int value)
{
    b[off] = cast(byte)(value & 0xff);
    b[off + 1] = cast(byte)((value >> 8) & 0xff);
}

private void put32(byte[] b, size_t off, long value)
{
    foreach (i; 0 .. 4)
        b[off + i] = cast(byte)((value >> (8 * i)) & 0xff);
}

private void put64(byte[] b, size_t off, long value)
{
    foreach (i; 0 .. 8)
        b[off + i] = cast(byte)((value >> (8 * i)) & 0xff);
}

@("the entry constructor keeps its name and rejects null or over-long names")
unittest
{
    auto entry = new ZipEntry("dir/file.txt");
    assert(entry.getName() == "dir/file.txt");
    assert(entry.toString() == "dir/file.txt");
    assert(entry.hashCode() == stringHashCode("dir/file.txt"));

    assertThrown!NullPointerException(new ZipEntry(cast(string) null));

    auto tooLong = new char[0x1_0000];
    assertThrown!IllegalArgumentException(new ZipEntry(tooLong.idup));
}

@("the copy constructor copies every field and rejects a null entry")
unittest
{
    auto source = new ZipEntry("a");
    source.setMethod(ZipEntry.DEFLATED);
    source.setCrc(0x1234_5678);
    source.setSize(41);
    source.setCompressedSize(17);
    source.setComment("note");
    source.setExtra([cast(byte) 1, cast(byte) 2, cast(byte) 3]);

    auto copy = new ZipEntry(source);
    assert(copy.getName() == "a");
    assert(copy.getMethod() == ZipEntry.DEFLATED);
    assert(copy.getCrc() == 0x1234_5678);
    assert(copy.getSize() == 41);
    assert(copy.getCompressedSize() == 17);
    assert(copy.getComment() == "note");
    assert(copy.getExtra() == source.getExtra());
    assert(source.csizeSet);

    assertThrown!NullPointerException(new ZipEntry(cast(ZipEntry) null));
}

@("the compression constants are Java's")
unittest
{
    assert(ZipEntry.STORED == 0);
    assert(ZipEntry.DEFLATED == 8);
}

@("size, crc and method setters keep Java's validation")
unittest
{
    auto entry = new ZipEntry("x");
    assert(entry.getSize() == -1);
    assert(entry.getCrc() == -1);
    assert(entry.getMethod() == -1);
    assert(entry.getCompressedSize() == -1);

    entry.setSize(0);
    assert(entry.getSize() == 0);
    assertThrown!IllegalArgumentException(entry.setSize(-1));

    entry.setCrc(0);
    entry.setCrc(0xFFFF_FFFF);
    assert(entry.getCrc() == 0xFFFF_FFFF);
    assertThrown!IllegalArgumentException(entry.setCrc(-1));
    assertThrown!IllegalArgumentException(entry.setCrc(0x1_0000_0000));

    entry.setMethod(ZipEntry.STORED);
    assert(entry.getMethod() == ZipEntry.STORED);
    entry.setMethod(ZipEntry.DEFLATED);
    assert(entry.getMethod() == ZipEntry.DEFLATED);
    assertThrown!IllegalArgumentException(entry.setMethod(9));

    entry.setCompressedSize(99);
    assert(entry.getCompressedSize() == 99);
}

@("names ending in a slash are directories")
unittest
{
    assert((new ZipEntry("dir/")).isDirectory());
    assert(!(new ZipEntry("dir")).isDirectory());
    assert(!(new ZipEntry("")).isDirectory());
}

@("the extra field round-trips and an over-long one is refused")
unittest
{
    auto entry = new ZipEntry("x");
    assert(entry.getExtra() is null);

    byte[] extra = [cast(byte) 0xAA, cast(byte) 0xBB, cast(byte) 0x02, cast(byte) 0x00, cast(byte) 0x01, cast(byte) 0x02];
    entry.setExtra(extra);
    assert(entry.getExtra() == extra);

    entry.setExtra(null);
    assert(entry.getExtra() is null);

    assertThrown!IllegalArgumentException(entry.setExtra(new byte[0x1_0000]));
}

@("a truncated extra field is ignored without reading past its end")
unittest
{
    auto entry = new ZipEntry("x");
    // tag 0x0001, size 16, but only one data byte follows.
    byte[] extra = [cast(byte) 0x01, cast(byte) 0x00, cast(byte) 0x10, cast(byte) 0x00, cast(byte) 0x7f];
    entry.setExtra(extra);
    assert(entry.getExtra() == extra);
}

@("the extended timestamp extra field sets the modification, access and creation times")
unittest
{
    auto entry = new ZipEntry("x");
    // Info-ZIP extended timestamp: flags 0x7, then mtime, atime and ctime as signed 32-bit seconds.
    byte[] extra = new byte[4 + 1 + 4 * 3];
    put16(extra, 0, 0x5455);
    put16(extra, 2, cast(int) extra.length - 4);
    extra[4] = 0x7;
    put32(extra, 5, 1_600_000_000);
    put32(extra, 9, 1_600_000_100);
    put32(extra, 13, 1_600_000_200);
    entry.setExtra(extra);

    assert(entry.getLastModifiedTime.get == FileTime.from(1_600_000_000, TimeUnit.SECONDS));
    assert(entry.getLastAccessTime.get == FileTime.from(1_600_000_100, TimeUnit.SECONDS));
    assert(entry.getCreationTime.get == FileTime.from(1_600_000_200, TimeUnit.SECONDS));
}

@("the extended timestamp CEN form carries only the modification time")
unittest
{
    auto entry = new ZipEntry("x");
    byte[] extra = new byte[4 + 1 + 4];
    put16(extra, 0, 0x5455);
    put16(extra, 2, cast(int) extra.length - 4);
    extra[4] = 0x1;
    put32(extra, 5, 1_500_000_000);
    entry.setExtra(extra);

    assert(entry.getLastModifiedTime.get == FileTime.from(1_500_000_000, TimeUnit.SECONDS));
    assert(entry.getLastAccessTime.isNull);
    assert(entry.getCreationTime.isNull);
}

@("the NTFS extra field sets the Windows file times and keeps an unavailable one absent")
unittest
{
    auto entry = new ZipEntry("x");
    byte[] extra = new byte[4 + 32];
    put16(extra, 0, 0x000a);
    put16(extra, 2, 32);
    // reserved 4 bytes at offset 4, then tag 0x0001 and size 24 at offset 8.
    put16(extra, 8, 0x0001);
    put16(extra, 10, 24);
    // 116444736000000000 * 100ns is the Unix epoch; a later time is +10,000,000 * 100ns (one second).
    put64(extra, 12, 116_444_736_000_000_000L);
    put64(extra, 20, long.min); // access time unavailable
    put64(extra, 28, 116_444_736_010_000_000L);
    entry.setExtra(extra);

    assert(entry.getLastModifiedTime.get == FileTime.from(0, TimeUnit.MILLISECONDS));
    assert(entry.getLastAccessTime.isNull);
    assert(entry.getCreationTime.get == FileTime.from(1_000, TimeUnit.MILLISECONDS));
}

@("the ZIP64 extra field fills the sizes for a CEN header")
unittest
{
    auto entry = new ZipEntry("x");
    entry.setSize(0xFFFF_FFFF);
    entry.setCompressedSize(0xFFFF_FFFF);
    byte[] extra = new byte[4 + 16];
    put16(extra, 0, 0x0001);
    put16(extra, 2, 16);
    put64(extra, 4, 0x1_0000_0001);
    put64(extra, 12, 0x1_0000_0002);
    entry.setExtra0(extra, true, false);
    assert(entry.getSize() == 0x1_0000_0001);
    assert(entry.getCompressedSize() == 0x1_0000_0002);
}

@("time setters and getters round-trip through DOS time")
unittest
{
    auto entry = new ZipEntry("x");
    entry.setTime(0);
    assert(entry.getTime() == 0);

    const millis = 1_589_693_289_000L; // 2020-05-15T12:34:49Z
    entry.setTime(millis);
    assert(entry.getTime() == millis);

    const local = LocalDateTime.of(2020, 5, 6, 7, 8, 9);
    entry.setTimeLocal(local);
    assert(entry.getTimeLocal() == local);

    const odd = LocalDateTime.of(2021, 12, 31, 23, 59, 59, 123_000_000);
    entry.setTimeLocal(odd);
    assert(entry.getTimeLocal() == odd);
}

@("the FileTime setters and getters keep the whole millisecond value")
unittest
{
    auto entry = new ZipEntry("x");
    assert(entry.getLastModifiedTime.isNull);
    assert(entry.getLastAccessTime.isNull);
    assert(entry.getCreationTime.isNull);

    const time = FileTime.from(1_589_693_289_123L, TimeUnit.MILLISECONDS);
    assert(entry.setLastModifiedTime(time) is entry);
    assert(entry.setLastAccessTime(time) is entry);
    assert(entry.setCreationTime(time) is entry);
    assert(entry.getLastModifiedTime.get == time);
    assert(entry.getLastAccessTime.get == time);
    assert(entry.getCreationTime.get == time);
    assert(entry.getTime() == 1_589_693_289_123L);

    // A value type cannot carry Java's null argument, so the throw-only overload does not exist (R5).
    static assert(!__traits(compiles, entry.setLastModifiedTime(null)));
    static assert(!__traits(compiles, entry.setLastAccessTime(null)));
    static assert(!__traits(compiles, entry.setCreationTime(null)));
    static assert(!__traits(compiles, entry.setTimeLocal(null)));
}

@("clone copies the entry and its extra field, including a null extra field")
unittest
{
    auto entry = new ZipEntry("x");
    auto empty = cast(ZipEntry) entry.clone();
    assert(empty.getName() == "x");
    assert(empty.getExtra() is null);

    entry.setExtra([cast(byte) 1, cast(byte) 2, cast(byte) 3]);
    auto copy = cast(ZipEntry) entry.clone();
    assert(copy.getExtra() == entry.getExtra());
    copy.getExtra()[0] = 9;
    assert(entry.getExtra()[0] == 1);
}

@("a default last modification time is built from the DOS time")
unittest
{
    auto entry = new ZipEntry("x");
    entry.setTime(1_000_000_000_000L);
    // setTime in the DOS range leaves mtime unset, so the getter rebuilds it from xdostime.
    const rebuilt = entry.getLastModifiedTime;
    assert(!rebuilt.isNull);
    assert(rebuilt.get.toMillis() == entry.getTime());
}

@("the default zone is UTC when a local time becomes an instant")
unittest
{
    auto entry = new ZipEntry("x");
    const local = LocalDateTime.of(2020, 1, 2, 3, 4, 5);
    entry.setTimeLocal(local);
    assert(entry.getLastModifiedTime.get.toInstant() == Instant.parse("2020-01-02T03:04:05Z"));
}
