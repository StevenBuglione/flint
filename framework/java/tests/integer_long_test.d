// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.lang.integer_long_test;

import flint.java.lang : ArithmeticException, NumberFormatException;
import flint.java.lang.integer : Integer;
import flint.java.lang.long_ : Long;

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

@("Integer and Long constants match Java")
unittest
{
    static assert(Integer.MIN_VALUE == int.min && Integer.MAX_VALUE == int.max && Integer.SIZE == 32
            && Integer.BYTES == 4);
    static assert(Long.MIN_VALUE == long.min && Long.MAX_VALUE == long.max && Long.SIZE == 64 && Long.BYTES == 8);
}

@("parseInt and parseLong accept Java's forms, including Unicode digits")
unittest
{
    assert(Integer.parseInt("2147483647") == int.max);
    assert(Integer.parseInt("-2147483648") == int.min);
    assert(Integer.parseInt("+0") == 0 && Integer.parseInt("-0") == 0);
    assert(Integer.parseInt("-80000000", 16) == int.min);
    assert(Integer.parseInt("zik0zj", 36) == int.max);
    assert(Integer.parseInt("١٢٣") == 123); // Arabic-Indic digits
    assert(Integer.parseInt("ｆｆ", 16) == 255); // fullwidth Latin letters
    assert(Long.parseLong("9223372036854775807") == long.max);
    assert(Long.parseLong("-9223372036854775808") == long.min);
    assert(Long.parseLong("-1y2p0ij32e8e8", 36) == long.min);
    assert(Long.parseLong("७") == 7); // Devanagari
    assert(Integer.valueOf("12", 8) == 10 && Long.valueOf("-12") == -12);
    assert(Integer.valueOf(5) == 5 && Long.valueOf(5L) == 5);
}

@("parseInt and parseLong report Java's messages")
unittest
{
    assert(failure({ Integer.parseInt("2147483648"); }) == `For input string: "2147483648"`);
    assert(failure({ Integer.parseInt("80000000", 16); }) == `For input string: "80000000" under radix 16`);
    assert(failure({ Integer.parseInt(""); }) == `For input string: ""`);
    assert(failure({ Integer.parseInt("-"); }) == `For input string: "-"`);
    assert(failure({ Integer.parseInt("1", 1); }) == "radix 1 less than Character.MIN_RADIX");
    assert(failure({ Long.parseLong("1", 37); }) == "radix 37 greater than Character.MAX_RADIX");
    assert(failure({ Long.parseLong("9223372036854775808"); }) == `For input string: "9223372036854775808"`);
    assert(failure({ Long.parseLong("1😀"); }) == `For input string: "1😀"`);
    assert(failure({ Long.parseLong("1\xC0\x81"); }) !is null); // overlong UTF-8 is no digit
}

@("parseUnsignedInt reaches 2^32 - 1 and reports Java's messages")
unittest
{
    assert(Integer.parseUnsignedInt("4294967295") == -1);
    assert(Integer.parseUnsignedInt("+2147483648") == int.min);
    assert(Integer.parseUnsignedInt("ffffffff", 16) == -1);
    const tooLarge = failure({ Integer.parseUnsignedInt("4294967296"); });
    assert(tooLarge == "String value 4294967296 exceeds range of unsigned int.");
    assert(failure({ Integer.parseUnsignedInt("-1"); }) == "Illegal leading minus sign on unsigned string -1.");
    assert(failure({ Integer.parseUnsignedInt("-1", 99); }) == "Illegal leading minus sign on unsigned string -1.");
    assert(failure({ Integer.parseUnsignedInt("", 16); }) == `For input string: "" under radix 16`);
    assert(failure({ Integer.parseUnsignedInt("", 99); }) == `For input string: "" under radix 99`);
    assert(failure({ Integer.parseUnsignedInt("1", 99); }) == "radix 99 greater than Character.MAX_RADIX");
    const overflow = failure({ Integer.parseUnsignedInt("99999999999999999999"); });
    assert(overflow == `For input string: "99999999999999999999"`);
}

@("parseUnsignedLong follows Java's split at the last digit")
unittest
{
    assert(Long.parseUnsignedLong("18446744073709551615") == -1);
    assert(Long.parseUnsignedLong("9223372036854775808") == long.min);
    assert(Long.parseUnsignedLong("ffffffffffffffff", 16) == -1);
    assert(Long.parseUnsignedLong("+18446744073709551615") == -1);
    assert(Long.parseUnsignedLong("3w5e11264sgsf", 36) == -1);
    const decimal = failure({ Long.parseUnsignedLong("18446744073709551616"); });
    assert(decimal == "String value 18446744073709551616 exceeds range of unsigned long.");
    const base36 = failure({ Long.parseUnsignedLong("3w5e11264sgsg", 36); });
    assert(base36 == "String value 3w5e11264sgsg exceeds range of unsigned long.");
    // Short text goes through parseLong(String), long text through parseLong(CharSequence, 0, len - 1).
    assert(failure({ Long.parseUnsignedLong("12345678901x"); }) == `For input string: "12345678901x"`);
    assert(failure({ Long.parseUnsignedLong("1234567890123456789x"); }) == "Bad digit at end of 1234567890123456789x");
    assert(failure({ Long.parseUnsignedLong("12345x7890123456789"); }) == `Error at index 5 in: "12345x789012345678"`);
    assert(failure({ Long.parseUnsignedLong("x234567890123456789"); }) == `Error at index 0 in: "x23456789012345678"`);
    assert(failure({ Long.parseUnsignedLong("+x34567890123456789"); }) == `Error at index 1 in: "+x3456789012345678"`);
    const prefixOverflow = failure({ Long.parseUnsignedLong("99999999999999999999"); });
    assert(prefixOverflow == `Error at index 18 in: "9999999999999999999"`);
    // UTF-16 indices: a supplementary character counts two units, and a split pair ends in U+FFFD.
    assert(failure({ Long.parseUnsignedLong("😀2345678901234", 16); }) == `Error at index 0 in: "😀234567890123"`);
    assert(failure({ Long.parseUnsignedLong("12345678901234😀", 16); }) == "Error at index 14 in: \"12345678901234�\"");
    assert(failure({ Long.parseUnsignedLong("١٢٣٤٥٦٧٨٩٠١٢٣"); }) is null);
    assert(failure({ Long.parseUnsignedLong("1", 0); }) == "radix 0 less than Character.MIN_RADIX");
    assert(failure({ Long.parseUnsignedLong("1234567890123", 37); }) == "radix 37 greater than Character.MAX_RADIX");
}

@("decode handles signs, radix prefixes and MIN_VALUE")
unittest
{
    assert(Integer.decode("-0x80000000") == int.min);
    assert(Integer.decode("#7fffffff") == int.max);
    assert(Integer.decode("010") == 8 && Integer.decode("0") == 0);
    assert(Long.decode("-0x8000000000000000") == long.min);
    assert(Long.decode("+0X7fffffffffffffff") == long.max);
    assert(failure({ Integer.decode(""); }) == "Zero length string");
    assert(failure({ Long.decode("0x-1"); }) == "Sign character in wrong position");
    assert(failure({ Integer.decode("0x80000000"); }) == `For input string: "80000000" under radix 16`);
    assert(failure({ Long.decode("-0x"); }) == `For input string: "-" under radix 16`);
    assert(failure({ Long.decode("09"); }) == `For input string: "9" under radix 8`);
}

@("toString and the unsigned text family match Java")
unittest
{
    assert(Integer.toString(int.min) == "-2147483648");
    assert(Integer.toString(-255, 16) == "-ff" && Integer.toString(255, 37) == "255");
    assert(Integer.toString(int.min, 2) == "-10000000000000000000000000000000");
    assert(Integer.toUnsignedString(-1) == "4294967295");
    assert(Integer.toUnsignedString(-1, 36) == "1z141z3");
    assert(Integer.toHexString(-1) == "ffffffff" && Integer.toHexString(0) == "0");
    assert(Integer.toOctalString(8) == "10" && Integer.toBinaryString(5) == "101");
    assert(Long.toString(long.min) == "-9223372036854775808");
    assert(Long.toString(long.min, 36) == "-1y2p0ij32e8e8");
    assert(Long.toUnsignedString(-1) == "18446744073709551615");
    assert(Long.toUnsignedString(-1, 36) == "3w5e11264sgsf");
    assert(Long.toUnsignedString(-1, 99) == "18446744073709551615");
    assert(Long.toHexString(long.min) == "8000000000000000");
    assert(Long.toOctalString(-1) == "1777777777777777777777");
    assert(Long.toBinaryString(0) == "0");
}

@("bit operations match Java")
unittest
{
    assert(Integer.highestOneBit(0) == 0 && Integer.highestOneBit(-1) == int.min && Integer.highestOneBit(100) == 64);
    assert(Integer.lowestOneBit(96) == 32 && Integer.lowestOneBit(0) == 0);
    assert(Integer.numberOfLeadingZeros(0) == 32 && Integer.numberOfLeadingZeros(1) == 31);
    assert(Integer.numberOfTrailingZeros(0) == 32 && Integer.numberOfTrailingZeros(int.min) == 31);
    assert(Integer.bitCount(-1) == 32 && Integer.bitCount(0xF0) == 4);
    assert(Integer.rotateLeft(1, 33) == 2 && Integer.rotateLeft(1, -1) == int.min);
    assert(Integer.rotateRight(1, 1) == int.min);
    assert(Integer.reverse(1) == int.min && Integer.reverseBytes(0x01020304) == 0x04030201);
    assert(Integer.signum(-5) == -1 && Integer.signum(0) == 0 && Integer.signum(int.max) == 1);
    assert(Integer.compress(0xCAFEBABE, 0xFF00FFF0) == 0xCABAB);
    assert(Integer.expand(0xCABAB, 0xFF00FFF0) == (0xCAFEBABE & 0xFF00FFF0));
    assert(Long.highestOneBit(0) == 0 && Long.highestOneBit(-1) == long.min);
    assert(Long.numberOfLeadingZeros(0) == 64 && Long.numberOfTrailingZeros(0) == 64);
    assert(Long.bitCount(-1) == 64 && Long.rotateLeft(1, 65) == 2 && Long.rotateRight(1, -63) == long.min);
    assert(Long.reverse(1) == long.min && Long.reverseBytes(0x0102030405060708) == 0x0807060504030201);
    assert(Long.compress(-1, 0xF0F0) == 0xFF && Long.expand(0xFF, 0xF0F0) == 0xF0F0);
    assert(Long.signum(long.min) == -1);
}

@("compare, hashCode and unsigned arithmetic match Java")
unittest
{
    assert(Integer.compare(int.min, int.max) == -1 && Integer.compare(3, 3) == 0);
    assert(Integer.compareUnsigned(-1, 1) == 1 && Long.compareUnsigned(1, -1) == -1);
    assert(Integer.toUnsignedLong(-1) == 0xFFFF_FFFFL);
    assert(Integer.divideUnsigned(-1, 2) == int.max && Integer.remainderUnsigned(-1, 2) == 1);
    assert(Long.divideUnsigned(-1, 2) == long.max && Long.remainderUnsigned(-1, 10) == 5);
    assert(Long.divideUnsigned(5, -1) == 0 && Long.remainderUnsigned(5, -1) == 5);
    assert(Integer.hashCode(-7) == -7 && Long.hashCode(-1) == 0 && Long.hashCode(1L << 32) == 1);
    assert(Integer.sum(int.max, 1) == int.min && Long.max(-1, 2) == 2 && Integer.min(-1, 2) == -1);

    int zero;
    string thrown;
    try
        Integer.divideUnsigned(1, zero);
    catch (ArithmeticException e)
        thrown = e.msg;
    assert(thrown == "/ by zero");
    thrown = null;
    try
        Long.remainderUnsigned(1, zero);
    catch (ArithmeticException e)
        thrown = e.msg;
    assert(thrown == "/ by zero");
}
