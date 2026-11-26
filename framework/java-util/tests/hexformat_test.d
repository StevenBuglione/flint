module hexformat_test;

import flint.java.lang : IllegalArgumentException, NumberFormatException;
import flint.java.util.hexformat : HexFormat;
import std.exception : assertThrown;
import std.conv : to;
import std.string : split, splitLines;

@safe:

@("HexFormat emits Java-width digits in the selected case")
unittest
{
    auto lower = HexFormat.of();
    auto upper = lower.withUpperCase();
    assert(!lower.isUpperCase());
    assert(upper.isUpperCase());
    assert(!upper.withLowerCase().isUpperCase());
    assert(lower.toHexDigits(cast(byte)-1) == "ff");
    assert(upper.toHexDigits(cast(byte) 0xA0) == "A0");
    assert(lower.toHexDigits(cast(short)-2) == "fffe");
    assert(upper.toHexDigits(cast(wchar) 0xd800) == "D800");
    assert(lower.toHexDigits(int.min) == "80000000");
    assert(upper.toHexDigits(int.max) == "7FFFFFFF");
    assert(lower.toHexDigits(long.min) == "8000000000000000");
    assert(upper.toHexDigits(-1L) == "FFFFFFFFFFFFFFFF");
    assert(lower.toHexDigits(0x12AB_CDEF, 3) == "def");
    assert(upper.toHexDigits(0x12AB_CDEF, 7) == "2ABCDEF");
    assert(upper.toHexDigits(0x12AB_CDEF, 0) == "");
    assertThrown!IllegalArgumentException(lower.toHexDigits(0L, -1));
    assertThrown!IllegalArgumentException(lower.toHexDigits(0L, 17));

    assert(lower.toHighHexDigit(-1) == 'f');
    assert(upper.toLowHexDigit(0x120C) == 'C');
    assert(upper.toHighHexDigit(0x12C0) == 'C');
}

@("HexFormat decodes only ASCII hexadecimal digits")
unittest
{
    foreach (index, digit; "0123456789abcdef")
    {
        assert(HexFormat.isHexDigit(digit));
        assert(HexFormat.fromHexDigit(digit) == index);
    }
    foreach (index, digit; "ABCDEF")
    {
        assert(HexFormat.isHexDigit(digit));
        assert(HexFormat.fromHexDigit(digit) == index + 10);
    }
    foreach (invalid; [-1, 0, '/', ':', 'G', 'g', 0xff10, 0xff21, 0x10030, int.max])
    {
        assert(!HexFormat.isHexDigit(invalid));
        assertThrown!NumberFormatException(HexFormat.fromHexDigit(invalid));
    }
}

@("HexFormat primitive widths and case agree with Java SE 21")
unittest
{
    auto lower = HexFormat.of();
    const auto upper = lower.withUpperCase();
    size_t rows;
    foreach (line; import("hexformat-java21.tsv").splitLines())
    {
        auto fields = line.split("\t");
        auto format = fields[0] == "true" ? upper : lower;
        const long value = fields[1].to!long;
        assert(format.toHexDigits(cast(byte) value) == fields[3], line);
        assert(format.toHexDigits(cast(wchar) value) == fields[4], line);
        assert(format.toHexDigits(cast(short) value) == fields[5], line);
        assert(format.toHexDigits(cast(int) value) == fields[6], line);
        assert(format.toHexDigits(value) == fields[7], line);
        assert(format.toHighHexDigit(cast(int) value) == fields[8][0], line);
        assert(format.toLowHexDigit(cast(int) value) == fields[9][0], line);
        assert(format.toHexDigits(value, fields[2].to!int) == fields[10][1 .. $ - 1], line);
        ++rows;
    }
    assert(rows == 306);
}

@("HexFormat decodes unsigned hexadecimal bit patterns at Java widths")
unittest
{
    assert(HexFormat.fromHexDigits("") == 0);
    assert(HexFormat.fromHexDigits("0fA") == 250);
    assert(HexFormat.fromHexDigits("80000000") == int.min);
    assert(HexFormat.fromHexDigits("ffffffff") == -1);
    assert(HexFormat.fromHexDigitsToLong("") == 0);
    assert(HexFormat.fromHexDigitsToLong("ffffffff") == 4_294_967_295L);
    assert(HexFormat.fromHexDigitsToLong("8000000000000000") == long.min);
    assert(HexFormat.fromHexDigitsToLong("ffffffffFFFFFFFF") == -1);
    assertThrown!IllegalArgumentException(HexFormat.fromHexDigits("000000000"));
    assertThrown!IllegalArgumentException(HexFormat.fromHexDigitsToLong("00000000000000000"));
    foreach (text; ["+1", "0x01", "１", "ééééé"])
    {
        assertThrown!NumberFormatException(HexFormat.fromHexDigits(text));
        assertThrown!NumberFormatException(HexFormat.fromHexDigitsToLong(text));
    }
    assertThrown!NumberFormatException(HexFormat.fromHexDigitsToLong("ééééééééé"));
    try
    {
        HexFormat.fromHexDigits("ééééééééé");
        assert(0, "Expected a Java width error");
    }
    catch (IllegalArgumentException failure)
    {
        assert(typeid(failure) is typeid(IllegalArgumentException));
    }
}
