module flint.java.format_test;

import flint.java.lang : IllegalArgumentException, String;
import flint.java.util.formatter : DuplicateFormatFlagsException, IllegalFormatConversionException,
    IllegalFormatException, MissingFormatArgumentException, UnknownFormatConversionException;

@safe:

// Expected values are JDK 21's String.format output for the same calls.

unittest
{
    assert(String.format("Hello, %s!", "World") == "Hello, World!");
    assert(String.format("%s %s", cast(Object) null, true) == "null true");
    assert(String.format("%5s|%-5s|%.2s", "ab", "ab", "abcdef") == "   ab|ab   |ab");
    assert(String.format("%S", "mixed Case") == "MIXED CASE");
    assert(String.format("%d", 42) == "42" && String.format("%d", -42L) == "-42");
    assert(String.format("%,d", 1_234_567) == "1,234,567");
    assert(String.format("%+d % d %(d", 5, 5, -5) == "+5  5 (5)");
    assert(String.format("%08d|%-8d|%8d", -42, 42, 42) == "-0000042|42      |      42");
    assert(String.format("%x %X %o", 255, 255, 8) == "ff FF 10");
    assert(String.format("%x", -1) == "ffffffff" && String.format("%x", -1L) == "ffffffffffffffff");
    assert(String.format("%#x %#o", 255, 8) == "0xff 010");
    assert(String.format("%c%c", 'A', 0x1F600) == "A\U0001F600");
    assert(String.format("%b %b %b %B", true, cast(Object) null, "x", false) == "true false true FALSE");
}

unittest
{
    assert(String.format("%f", 3.14159265) == "3.141593");
    assert(String.format("%.2f", 2.675) == "2.68"); // half up on Double.toString's digits
    assert(String.format("%.0f", 2.5) == "3");
    assert(String.format("%10.3f|%-10.3f|%010.3f", -1.5, 1.5, -1.5) == "    -1.500|1.500     |-00001.500");
    assert(String.format("%,.2f", 1_234_567.891) == "1,234,567.89");
    assert(String.format("%.3f", 9.9999) == "10.000" && String.format("%.2f", 1e-5) == "0.00");
    assert(String.format("%.1f", 1e21) == "1000000000000000000000.0");
    assert(String.format("%s", 1.0) == "1.0" && String.format("%s", 100.0f) == "100.0");
    assert(String.format("%s", 1e21) == "1.0E21");
}

unittest
{
    assert(String.format("%2$s %1$s", "a", "b") == "b a");
    assert(String.format("%s %<s %s", "a", "b") == "a a b");
    assert(String.format("100%% done%n") == "100% done\n");
    assert(String.format("no specifiers") == "no specifiers");
}

unittest
{
    import std.exception : collectException;

    auto missing = collectException!MissingFormatArgumentException(String.format("%s %s", "only"));
    assert(missing !is null && missing.msg == "Format specifier '%s'");
    auto unknown = collectException!UnknownFormatConversionException(String.format("%q", "x"));
    assert(unknown !is null && unknown.msg == "Conversion = 'q'");
    auto illegal = collectException!IllegalFormatConversionException(String.format("%d", "x"));
    assert(illegal !is null && illegal.msg == "d != java.lang.String");
    assert(collectException!IllegalFormatConversionException(String.format("%c", "x")).msg == "c != java.lang.String");
    // Every one is an IllegalArgumentException, as in Java.
    assert(collectException!IllegalArgumentException(String.format("%", "x")) !is null);
}

@("String.format: a text longer than the formatter's stack buffer is whole, and an empty format is empty")
unittest
{
    import std.array : replicate;

    const chunk = "x".replicate(250);
    assert(String.format("%s-%s-%s", chunk, chunk, "end") == chunk ~ "-" ~ chunk ~ "-end");
    assert(String.format("%s", "y".replicate(300)) == "y".replicate(300));
    assert(String.format("%300s", "r").length == 300);
    assert(String.format("").length == 0);
}

@("String.format reports invalid specifiers before resolving arguments") unittest
{
    import std.exception : collectException;

    assert(collectException!UnknownFormatConversionException(String.format("%s %q")).getConversion() == "q");
    assert(collectException!UnknownFormatConversionException(String.format("%0$")).getConversion() == "0");
    assert(collectException!UnknownFormatConversionException(String.format("%é")).getConversion() == "é");
    assert(collectException!UnknownFormatConversionException(String.format("%😀")).getConversion() == "\uFFFD");
    assert(collectException!UnknownFormatConversionException(String.format("%\xFF")).getConversion() == "\uFFFD");
    const duplicate = collectException!DuplicateFormatFlagsException(String.format("%--5s"));
    assert(duplicate.getFlags() == "-");
    assert(duplicate.getMessage() == "Flags = '-'");
    assert((new DuplicateFormatFlagsException(null)).getMessage() == "Flags = ''"); // R26
    assert(collectException!DuplicateFormatFlagsException(String.format("%s %<<s")).getFlags() == "<");
    const badIndex = collectException!IllegalFormatException(String.format("%s %0$s"));
    assert(badIndex.msg == "Illegal format argument index = 0");
    const overflowingIndex = collectException!IllegalFormatException(String.format("%2147483648$s"));
    assert(overflowingIndex.msg == "Format argument index: (not representable as int)");
    const indexBeforeFlags = collectException!IllegalFormatException(String.format("%0$--5s"));
    assert(indexBeforeFlags.msg == "Illegal format argument index = 0");
    assert(collectException!MissingFormatArgumentException(String.format("%e")).getFormatSpecifier() == "%e");
    assert(collectException!MissingFormatArgumentException(String.format("%tY")).getFormatSpecifier() == "%tY");
    assert(collectException!UnknownFormatConversionException(String.format("%Tq")).getConversion() == "tq");
}

@("String.format validates formats beyond the cached specifiers") unittest
{
    import std.exception : collectException;

    assert(String.format("%s %-<5s", "a") == "a a    ");
    assert(String.format("%s/%s/%s/%s/%s/%s", "a", "b", "c", "d", "e", "f") == "a/b/c/d/e/f");
    assert(collectException!UnknownFormatConversionException(String.format("%s/%s/%s/%s/%q")).getConversion() == "q");
}

@("String.format counts UTF-16 code units for width and precision")
unittest
{
    assert(String.format("[%4s][%-4s][%4c]", "😀", "é", 0x1f600) == "[  😀][é   ][  😀]");
    assert(String.format("[%1s]", "😀") == "[😀]");
    assert(String.format("%.1s|%.2s|%.3s", "éz", "😀x", "é😀x") == "é|😀|é😀");
    assert(String.format("[%.1s][%.2s]", "😀x", "é😀x") == "[\ufffd][é\ufffd]");
    assert(String.format("[%4.2S][%3.0s]", "a😀z", "é") == "[  A\ufffd][   ]");
}

@("String.format validates widths, precisions and flags before resolving arguments")
unittest
{
    import std.exception : collectException;

    void check(string format, string message)
    {
        const error = collectException!IllegalFormatException(String.format(format));
        assert(error !is null && error.getMessage() == message, format);
    }

    check("%2147483648s", "-2147483648");
    check("%.2147483648s", "-2147483648");
    check("%2$+-S", "%-+2$S");
    check("%+ 3X", "Flags = '^+ '");
    check("% +s", "Conversion = s, Flags = + ");
    check("%#-b", "Conversion = b, Flags = #");
    check("%s %#d", "Conversion = d, Flags = #");
    check("%-0.2d", "%-0.2d");
    check("%-.2Tq", "2");
    check("%-Tp", "%-TP");
    check("%+5n", "5");
    check("%5.2n", "2");
    check("%,+n", "Flags = '+,'");
    assert(String.format("%-3%|%%|%n") == "%  |%|\n");
}

@("Formatter validation exceptions retain their diagnostic payloads")
unittest
{
    import flint.java.util.formatter : FormatFlagsConversionMismatchException, IllegalFormatFlagsException,
        IllegalFormatPrecisionException, IllegalFormatWidthException, MissingFormatWidthException;
    import std.exception : collectException;

    const width = collectException!IllegalFormatWidthException(String.format("%2147483648s"));
    assert(width.getWidth() == int.min);
    const precision = collectException!IllegalFormatPrecisionException(String.format("%.2d"));
    assert(precision.getPrecision() == 2);
    const flags = collectException!IllegalFormatFlagsException(String.format("%+ 3X"));
    assert(flags.getFlags() == "^+ ");
    const missing = collectException!MissingFormatWidthException(String.format("%2$+-S"));
    assert(missing.getFormatSpecifier() == "%-+2$S");
    const mismatch = collectException!FormatFlagsConversionMismatchException(String.format("%#2B"));
    assert(mismatch.getFlags() == "#" && mismatch.getConversion() == 'b');

    const surrogate = new FormatFlagsConversionMismatchException(null, cast(wchar) 0xD800);
    assert(surrogate.getFlags().length == 0 && surrogate.getConversion() == 0xD800);
    assert(surrogate.getMessage() == "Conversion = \uFFFD, Flags = ");
    assert((new IllegalFormatFlagsException(null)).getMessage() == "Flags = ''");
    assert((new MissingFormatWidthException(null)).getFormatSpecifier().length == 0);
}

@("String.format keeps radix indicators before zeros and preserves integer bit widths")
unittest
{
    assert(String.format("%#08x|%#08X|%#06o", 255, 255, 8) == "0x0000ff|0X0000FF|000010");
    assert(String.format("%#X|%#o|%#02x", 0, 0, 255) == "0X0|00|0xff");
    assert(String.format("[%#8X][%-#8X]", 255, 255) == "[    0XFF][0XFF    ]");
    assert(String.format("%#06X|%#08x", cast(byte)-1, cast(short)-1) == "0X00FF|0x00ffff");
    assert(String.format("%#012x|%#020x", -1, -1L) == "0x00ffffffff|0x00ffffffffffffffff");
    assert(String.format("[%#08X][%#08x]", cast(Object) null, cast(Object) null) == "[    NULL][    null]");
    assert(String.format("%(08d|%+08.2f", -42, 1.5) == "(000042)|+0001.50");
}

@("String.format rejects sign flags after checking the radix argument type")
unittest
{
    import flint.java.util.formatter : FormatFlagsConversionMismatchException;
    import std.exception : collectException;

    const mismatch = collectException!FormatFlagsConversionMismatchException(String.format("%(+X", 17));
    assert(mismatch.getConversion() == 'x' && mismatch.getFlags() == "+(");
    const wrongType = collectException!IllegalFormatConversionException(String.format("%(+X", "bad"));
    assert(wrongType.getMessage() == "x != java.lang.String");
    const staticMismatch = collectException!FormatFlagsConversionMismatchException(String.format("%,+X", "bad"));
    assert(staticMismatch.getFlags() == ",");
    assert(String.format("%+(8X", cast(Object) null) == "    NULL");
}

@("String.format reports missing arguments with Java's canonical specifier")
unittest
{
    import std.exception : collectException;

    const explicit = collectException!MissingFormatArgumentException(String.format("%2$-10.004S", "one"));
    assert(explicit.getFormatSpecifier() == "%-2$10.4S");
    assert(explicit.getMessage() == "Format specifier '%-2$10.4S'");
    const radix = collectException!MissingFormatArgumentException(String.format("%003$#08X"));
    assert(radix.getFormatSpecifier() == "%#03$8X");
    const relative = collectException!MissingFormatArgumentException(String.format("%02$<-9S"));
    assert(relative.getFormatSpecifier() == "%-<9S");
    const date = collectException!MissingFormatArgumentException(String.format("%02$4Tp"));
    assert(date.getFormatSpecifier() == "%2$4TP");
    const tail = collectException!MissingFormatArgumentException(String.format("%s/%s/%s/%s/%09$-7.000s",
            "a", "b", "c", "d"));
    assert(tail.getFormatSpecifier() == "%-9$7.0s");
    assert(String.format("%2$s %s %<s %s", "a", "b") == "b a a b");
}

@("String.format reports Java's character code-point and type diagnostics")
unittest
{
    import flint.java.util.formatter : IllegalFormatCodePointException;
    import std.exception : collectException;

    const negative = collectException!IllegalFormatCodePointException(String.format("%c", cast(byte)-1));
    assert(negative.getCodePoint() == -1 && negative.getMessage() == "Code point = 0xffffffff");
    const tooLarge = collectException!IllegalFormatCodePointException(String.format("%c", 0x110000));
    assert(tooLarge.getCodePoint() == 0x110000 && tooLarge.getMessage() == "Code point = 0x110000");
    assert((new IllegalFormatCodePointException(int.min)).getMessage() == "Code point = 0x80000000");
    const longArgument = collectException!IllegalFormatConversionException(String.format("%c", 65L));
    assert(longArgument.getMessage() == "c != java.lang.Long");
    assert(String.format("[%3c][%3c]", cast(wchar) 0xd800, 0xdfff) == "[  \uFFFD][  \uFFFD]");
    assert(String.format("[%3c]", 0x1f600) == "[ 😀]");
    assert(String.format("%c", 65u) == "A");
}

@("String.format rounds scientific mantissas using Java's shortest decimal digits")
unittest
{
    assert(String.format("%e|%e|%.0e", 125.0, -0.0, 2.5) == "1.250000e+02|-0.000000e+00|3e+00");
    assert(String.format("%.2e|%.2e|%.0e", 2.675, 9.999, 95.0) == "2.68e+00|1.00e+01|1e+02");
    assert(String.format("%.2e|%#.0e", 0.00009995, 1.25) == "1.00e-04|1.e+00");
    assert(String.format("%.2E|%.15e", 1.25e-125,
            double.min_normal * double.epsilon) == "1.25E-125|4.900000000000000e-324");
    assert(String.format("%.10e", 1.2345f) == "1.2345000505e+00");
}

@("String.format applies scientific width, signs and case")
unittest
{
    import std.exception : collectException;

    assert(String.format("[%+012.3e][%(012.2E]", 1.5, -1.25) == "[+001.500e+00][(001.25E+00)]");
    assert(String.format("[% 012E][%+010E][%010E]", double.infinity, double.nan,
            cast(Object) null) == "[    INFINITY][       NAN][      NULL]");
    const wrongType = collectException!IllegalFormatConversionException(String.format("%E", 7));
    assert(wrongType.getMessage() == "e != java.lang.Integer");
}

@("String.format chooses general notation after rounding and retains significant zeros")
unittest
{
    assert(String.format("%g|%g|%.0g|%.0g", 1.25, -0.0, 0.0, 9.5) == "1.25000|-0.00000|0|1e+01");
    assert(String.format("%.3g|%.3g|%.3g", 0.0000994, 0.0001, 0.00009995) == "9.94e-05|0.000100|0.000100");
    assert(String.format("%.3g|%.3g|%.3g", 999.4, 999.5, 1000.0) == "999|1.00e+03|1.00e+03");
    assert(String.format("%,.7g|%,.3g|%0,14.5g", 12_345.0, 12_345.0, 1234.0) == "12,345.00|1.23e+04|00000001,234.0");
}

@("String.format applies general signs and uppercase rendering")
unittest
{
    import std.exception : collectException;

    assert(String.format("[%+012.4g][%(012.4G]", 0.125, -12_345.0) == "[+000000.1250][(01.235E+04)]");
    assert(String.format("[%+012G][%+010G][%010G]", double.infinity, double.nan,
            cast(Object) null) == "[   +INFINITY][       NAN][      NULL]");
    const wrongType = collectException!IllegalFormatConversionException(String.format("%G", 7));
    assert(wrongType.getMessage() == "g != java.lang.Integer");
}

@("String.format rounds hexadecimal floating values to even")
unittest
{
    assert(String.format("%a|%A|%.0a", 0.0, -0.0, 1.0) == "0x0.0p0|-0X0.0P0|0x1.0p0");
    assert(String.format("%.1a|%.1a|%.1a", 1.03125, 1.09375, 1.96875) == "0x1.0p0|0x1.2p0|0x1.0p1");
    const tiny = double.min_normal * double.epsilon;
    assert(String.format("%a|%.12a|%.13A", tiny, tiny,
            tiny) == "0x0.0000000000001p-1022|0x1.000000000000p-1074|0X0.0000000000001P-1022");
    assert(String.format("%.1A", double.max) == "0X1.0P1024");
}

@("String.format applies hexadecimal floating width before precision padding")
unittest
{
    import std.exception : collectException;

    assert(String.format("[%+014A][%020.6a]", 1.5, 1.0) == "[+0X0000001.8P0][0x00000000000001.000000p0]");
    assert(String.format("[%012A][%+012A]", cast(Object) null, double.nan) == "[        NULL][         NAN]");
    const wrongType = collectException!IllegalFormatConversionException(String.format("%A", 7));
    assert(wrongType.getMessage() == "a != java.lang.Integer");
}
