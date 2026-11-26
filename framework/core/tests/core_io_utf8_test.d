module flint.core.io_utf8_test;

import flint.core.io : ByteArrayResource;

@safe:

private string decoded(immutable(ubyte)[] bytes)
{
    return new ByteArrayResource(bytes).getContentAsString();
}

private enum string r = "�";

@("getContentAsString replaces malformed UTF-8 as Java's InputStreamReader does")
unittest
{
    // Expected texts are OpenJDK 21.0.13 InputStreamReader(UTF_8) results for the same bytes.
    assert(decoded([0x61, 0x80, 0x62]) == "a" ~ r ~ "b"); // a stray continuation byte
    assert(decoded([0xC0, 0x80]) == r ~ r); // overlong two-byte encoding of NUL
    assert(decoded([0xC1, 0xBF]) == r ~ r);
    assert(decoded([0xE0, 0x80, 0x80]) == r ~ r ~ r); // overlong three-byte encoding
    assert(decoded([0xF0, 0x80, 0x80, 0x80]) == r ~ r ~ r ~ r); // overlong four-byte encoding
    assert(decoded([0xED, 0xA0, 0x80]) == r); // a surrogate is one malformed input of three bytes
    assert(decoded([0xE1, 0x80, 0x41]) == r ~ "A"); // broken at the third byte
    assert(decoded([0xF0, 0x9F, 0x41]) == r ~ "A");
    assert(decoded([0xF4, 0x90, 0x80, 0x80]) == r ~ r ~ r ~ r); // above U+10FFFF
    assert(decoded([0xF5, 0x80]) == r ~ r);
    assert(decoded([0xF8, 0x88, 0x80, 0x80, 0x80]) == r ~ r ~ r ~ r ~ r);
    assert(decoded([0xFF]) == r);
    assert(decoded([0xC2, 0x41]) == r ~ "A");
}

@("getContentAsString replaces a truncated UTF-8 tail with one character")
unittest
{
    assert(decoded([0x78, 0xE2, 0x82]) == "x" ~ r);
    assert(decoded([0xF0, 0x9F, 0x98]) == r);
    assert(decoded([0xED, 0xA0]) == r);
    assert(decoded([0xE0, 0xA0]) == r);
    assert(decoded([0xC2]) == r);
}

@("getContentAsString keeps valid UTF-8 unchanged")
unittest
{
    // U+20AC, U+1F600, U+D7FF, U+E000 and U+10FFFF: the edges of the valid ranges.
    immutable(ubyte)[] valid = [
        0xE2, 0x82, 0xAC, 0xF0, 0x9F, 0x98, 0x80, 0xED, 0x9F, 0xBF, 0xEE, 0x80, 0x80, 0xF4, 0x8F, 0xBF,
        0xBF
    ];
    assert(decoded(valid) == cast(string) valid);
    assert(decoded(cast(immutable(ubyte)[]) "") == "");
}
