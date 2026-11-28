// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the Java pathname value contract. */
module flint.java.io.file_value_contract_test;

import flint.java.io : File;
import flint.java.lang : NullPointerException;
import std.exception : assertThrown;

@safe:

@("File compares equal when the pathname strings are equal")
unittest
{
    auto first = new File("/tmp/a");
    auto same = new File("/tmp/a");
    auto other = new File("/tmp/b");

    assert(first == same);
    assert(first != other);
    assert(first.equals(same));
    assert(!first.equals(other));
    assert(!first.equals(null));
    assert(first.equals(cast(Object) same));
    assert(!first.equals(new Object));
}

@("File hashes the pathname with Java's String.hashCode")
unittest
{
    assert(new File("abc").hashCode() == 31 * 31 * 'a' + 31 * 'b' + 'c');
    assert(new File("\U00010000").hashCode() == 31 * 0xD800 + 0xDC00);
}

@("File orders pathnames by UTF-16 code unit")
unittest
{
    auto first = new File("a");
    auto second = new File("b");

    assert(first.compareTo(second) < 0);
    assert(second.compareTo(first) > 0);
    assert(first.compareTo(new File("a")) == 0);
    assert(first < second);
    assert(second > first);
}

@("File compares supplementary characters by UTF-16 code units, not UTF-8 bytes")
unittest
{
    auto supplementary = new File("\U00010000");
    auto bmp = new File("\uE000");

    assert(supplementary.compareTo(bmp) < 0);
    assert(bmp.compareTo(supplementary) > 0);
}

@("File.compareTo rejects a null argument")
unittest
{
    assertThrown!NullPointerException(new File("a").compareTo(null));
}

@("File value equality keys associative arrays")
unittest
{
    int[File] seen;
    seen[new File("/x")] = 7;
    assert(seen[new File("/x")] == 7);
}
