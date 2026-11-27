// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.lang.byte_short_test;

import flint.java.lang : NumberFormatException;
import flint.java.lang.byte_ : Byte;
import flint.java.lang.short_ : Short;

@safe:

// The message of the NumberFormatException `fn` throws, or null when it returns.
private string failure(scope void delegate() @safe fn)
{
    try
        fn();
    catch (NumberFormatException e)
        return e.msg.length ? e.msg : "(empty)";
    return null;
}

@("Byte and Short constants match Java")
unittest
{
    static assert(Byte.MIN_VALUE == -128 && Byte.MAX_VALUE == 127 && Byte.SIZE == 8 && Byte.BYTES == 1);
    static assert(Short.MIN_VALUE == -32_768 && Short.MAX_VALUE == 32_767 && Short.SIZE == 16 && Short.BYTES == 2);
    static assert(is(typeof(Byte.MIN_VALUE) == byte) && is(typeof(Short.MAX_VALUE) == short));
}

@("parseByte and parseShort accept Java's forms in every radix")
unittest
{
    assert(Byte.parseByte("127") == 127);
    assert(Byte.parseByte("-128") == -128);
    assert(Byte.parseByte("+0") == 0);
    assert(Byte.parseByte("-0") == 0);
    assert(Byte.parseByte("0000000127") == 127);
    assert(Byte.parseByte("7f", 16) == 127);
    assert(Byte.parseByte("-80", 16) == -128);
    assert(Byte.parseByte("-1111111", 2) == -127);
    assert(Byte.parseByte("3J", 36) == 127 && Byte.parseByte("-3K", 36) == -128);
    assert(Short.parseShort("32767") == 32_767);
    assert(Short.parseShort("-32768") == -32_768);
    assert(Short.parseShort("-8000", 16) == -32_768);
    assert(Short.parseShort("zz", 36) == 35 * 36 + 35);
    assert(Byte.valueOf("12") == 12 && Byte.valueOf("-c", 16) == -12);
    assert(Short.valueOf("-300") == -300 && Short.valueOf("777", 8) == 511);
    assert(Byte.valueOf(cast(byte)-5) == -5 && Short.valueOf(cast(short) 9) == 9);
}

@("Character.digit's Unicode digits and fullwidth letters parse as in Java")
unittest
{
    assert(Byte.parseByte("١٢") == 12); // Arabic-Indic one, two
    assert(Byte.parseByte("-९") == -9); // Devanagari nine
    assert(Short.parseShort("１００") == 100); // fullwidth 1 0 0
    assert(Short.parseShort("Ｆｆ", 16) == 0xFF); // fullwidth F and f
    assert(Short.parseShort("Ｚ", 36) == 35); // fullwidth Z
    assert(Byte.parseByte("꯹") == 9); // Meetei Mayek nine, the last BMP block in the table
}

@("parse failures throw NumberFormatException with Java's messages")
unittest
{
    assert(failure({ Byte.parseByte("128"); }) == `Value out of range. Value:"128" Radix:10`);
    assert(failure({ Byte.parseByte("-81", 16); }) == `Value out of range. Value:"-81" Radix:16`);
    assert(failure({ Short.parseShort("32768"); }) == `Value out of range. Value:"32768" Radix:10`);
    assert(failure({ Short.parseShort("2147483648"); }) == `For input string: "2147483648"`);
    assert(failure({ Short.parseShort("-2147483648"); }) == `Value out of range. Value:"-2147483648" Radix:10`);
    assert(failure({ Byte.parseByte(""); }) == `For input string: ""`);
    assert(failure({ Byte.parseByte("", 16); }) == `For input string: "" under radix 16`);
    assert(failure({ Byte.parseByte("+"); }) == `For input string: "+"`);
    assert(failure({ Byte.parseByte("-"); }) == `For input string: "-"`);
    assert(failure({ Byte.parseByte("+-1"); }) == `For input string: "+-1"`);
    assert(failure({ Byte.parseByte(" 1"); }) == `For input string: " 1"`);
    assert(failure({ Byte.parseByte("1 "); }) == `For input string: "1 "`);
    assert(failure({ Byte.parseByte("8", 8); }) == `For input string: "8" under radix 8`);
    assert(failure({ Byte.parseByte("1", 1); }) == "radix 1 less than Character.MIN_RADIX");
    assert(failure({ Byte.parseByte("1", 37); }) == "radix 37 greater than Character.MAX_RADIX");
    assert(failure({ Short.parseShort("", -5); }) == "radix -5 less than Character.MIN_RADIX");
    assert(failure({ Short.parseShort("\U0001D7CE"); }) == "For input string: \"\U0001D7CE\""); // math bold 0
    assert(failure({ Short.parseShort("²"); }) == "For input string: \"²\""); // superscript two
    assert(failure({ Short.parseShort("Ⅷ"); }) == "For input string: \"Ⅷ\""); // Roman numeral eight
}

@("parsing rejects malformed and overlong UTF-8 instead of reading a digit")
unittest
{
    immutable string overlongFive = "\xC0\xB5";
    immutable string truncated = "1\xD9";
    assert(failure({ Byte.parseByte(overlongFive); }) !is null);
    assert(failure({ Byte.parseByte(truncated); }) !is null);
}

@("decode reads signs and radix prefixes as Integer.decode does")
unittest
{
    assert(Short.decode("10") == 10 && Short.decode("0x10") == 16 && Short.decode("0X10") == 16);
    assert(Short.decode("010") == 8 && Short.decode("#10") == 16 && Short.decode("0") == 0);
    assert(Short.decode("+#10") == 16 && Short.decode("-010") == -8 && Short.decode("-0x8000") == -32_768);
    assert(Byte.decode("-0x80") == -128 && Byte.decode("0177") == 127 && Byte.decode("#7F") == 127);
    assert(Byte.decode("-0") == 0 && Byte.decode("00") == 0);
    assert(Byte.decode("0٧") == 7); // a leading 0 selects octal, and Arabic-Indic seven is an octal digit
}

@("decode failures throw Java's messages, naming the signed digits Java retried")
unittest
{
    assert(failure({ Short.decode(""); }) == "Zero length string");
    assert(failure({ Short.decode("0x-10"); }) == "Sign character in wrong position");
    assert(failure({ Short.decode("-+1"); }) == "Sign character in wrong position");
    assert(failure({ Short.decode("+"); }) == `For input string: ""`);
    assert(failure({ Short.decode("-"); }) == `For input string: "-"`);
    assert(failure({ Short.decode("0x"); }) == `For input string: "" under radix 16`);
    assert(failure({ Short.decode("-#"); }) == `For input string: "-" under radix 16`);
    assert(failure({ Short.decode("0x1G"); }) == `For input string: "1G" under radix 16`);
    assert(failure({ Short.decode("-09"); }) == `For input string: "-9" under radix 8`);
    assert(failure({ Short.decode("1_0"); }) == `For input string: "1_0"`);
    assert(failure({ Short.decode("32768"); }) == "Value 32768 out of range from input 32768");
    assert(failure({ Short.decode("-0x8001"); }) == "Value -32769 out of range from input -0x8001");
    assert(failure({ Byte.decode("0x80"); }) == "Value 128 out of range from input 0x80");
    assert(failure({ Byte.decode("-2147483648"); }) == "Value -2147483648 out of range from input -2147483648");
    assert(failure({ Byte.decode("2147483648"); }) == `For input string: "2147483648"`);
}

@("toString, hashCode, compare and the unsigned conversions match Java")
unittest
{
    assert(Byte.toString(Byte.MIN_VALUE) == "-128" && Byte.toString(0) == "0" && Byte.toString(99) == "99");
    assert(Short.toString(Short.MIN_VALUE) == "-32768" && Short.toString(Short.MAX_VALUE) == "32767");
    assert(Byte.hashCode(-1) == -1 && Short.hashCode(-300) == -300);
    assert(Byte.compare(-128, 127) == -255 && Byte.compare(5, 5) == 0);
    assert(Short.compare(Short.MAX_VALUE, Short.MIN_VALUE) == 65_535);
    assert(Byte.compareUnsigned(-1, 1) == 254 && Byte.compareUnsigned(0, -128) == -128);
    assert(Short.compareUnsigned(1, -1) == -65_534);
    assert(Byte.toUnsignedInt(-1) == 255 && Byte.toUnsignedLong(-128) == 128L);
    assert(Short.toUnsignedInt(-1) == 65_535 && Short.toUnsignedLong(Short.MIN_VALUE) == 32_768L);
    assert(Short.reverseBytes(0x1234) == 0x3412);
    assert(Short.reverseBytes(cast(short) 0x80FF) == cast(short) 0xFF80);
    assert(Short.reverseBytes(-1) == -1 && Short.reverseBytes(0x00FF) == cast(short) 0xFF00);
}

@("the non-throwing statics stay pure nothrow @nogc")
pure nothrow @nogc unittest
{
    assert(Byte.compare(1, 2) < 0 && Short.reverseBytes(0x0102) == 0x0201);
    assert(Byte.toUnsignedInt(-2) == 254 && Short.hashCode(7) == 7 && Byte.valueOf(cast(byte) 3) == 3);
}
