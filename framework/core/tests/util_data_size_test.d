// Ported from spring-framework v7.1.0: spring-core/src/test/java/org/springframework/util/unit
// Copyright 2002-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
/++
Port of spring-core's `org.springframework.util.unit.DataSizeTests` (v7.1.0): one `unittest` per Java test method,
each starting with a `// <JavaTestName>` comment. None are skipped. The two null-default-unit tests also assert that a
`null` `DataUnit` does not compile, since it is a D enum (R20).
+/
module flint.util.data_size_tests;

import flint.java.lang : IllegalArgumentException;
import flint.util.unit : DataSize, DataUnit;

@safe:

@("ofBytesToBytes")
unittest
{
    // ofBytesToBytes
    assert(DataSize.ofBytes(1024).toBytes() == 1024);
}

@("ofBytesToKilobytes")
unittest
{
    // ofBytesToKilobytes
    assert(DataSize.ofBytes(1024).toKilobytes() == 1);
}

@("ofKilobytesToKilobytes")
unittest
{
    // ofKilobytesToKilobytes
    assert(DataSize.ofKilobytes(1024).toKilobytes() == 1024);
}

@("ofKilobytesToMegabytes")
unittest
{
    // ofKilobytesToMegabytes
    assert(DataSize.ofKilobytes(1024).toMegabytes() == 1);
}

@("ofMegabytesToMegabytes")
unittest
{
    // ofMegabytesToMegabytes
    assert(DataSize.ofMegabytes(1024).toMegabytes() == 1024);
}

@("ofMegabytesToGigabytes")
unittest
{
    // ofMegabytesToGigabytes
    assert(DataSize.ofMegabytes(2048).toGigabytes() == 2);
}

@("ofGigabytesToGigabytes")
unittest
{
    // ofGigabytesToGigabytes
    assert(DataSize.ofGigabytes(4096).toGigabytes() == 4096);
}

@("ofGigabytesToTerabytes")
unittest
{
    // ofGigabytesToTerabytes
    assert(DataSize.ofGigabytes(4096).toTerabytes() == 4);
}

@("ofTerabytesToGigabytes")
unittest
{
    // ofTerabytesToGigabytes
    assert(DataSize.ofTerabytes(1).toGigabytes() == 1024);
}

@("ofWithBytesUnit")
unittest
{
    // ofWithBytesUnit
    assert(DataSize.of(10, DataUnit.BYTES) == DataSize.ofBytes(10));
}

@("ofWithKilobytesUnit")
unittest
{
    // ofWithKilobytesUnit
    assert(DataSize.of(20, DataUnit.KILOBYTES) == DataSize.ofKilobytes(20));
}

@("ofWithMegabytesUnit")
unittest
{
    // ofWithMegabytesUnit
    assert(DataSize.of(30, DataUnit.MEGABYTES) == DataSize.ofMegabytes(30));
}

@("ofWithGigabytesUnit")
unittest
{
    // ofWithGigabytesUnit
    assert(DataSize.of(40, DataUnit.GIGABYTES) == DataSize.ofGigabytes(40));
}

@("ofWithTerabytesUnit")
unittest
{
    // ofWithTerabytesUnit
    assert(DataSize.of(50, DataUnit.TERABYTES) == DataSize.ofTerabytes(50));
}

@("parseWithDefaultUnitUsesBytes")
unittest
{
    // parseWithDefaultUnitUsesBytes
    assert(DataSize.parse("1024") == DataSize.ofKilobytes(1));
}

@("parseNegativeNumberWithDefaultUnitUsesBytes")
unittest
{
    // parseNegativeNumberWithDefaultUnitUsesBytes
    assert(DataSize.parse("-1") == DataSize.ofBytes(-1));
}

@("parseWithNullDefaultUnitUsesBytes")
unittest
{
    // parseWithNullDefaultUnitUsesBytes
    // DataUnit is a D enum, so a null default unit does not compile (R20); parse(text) is the bytes default.
    static assert(!__traits(compiles, DataSize.parse("1024", null)));
    assert(DataSize.parse("1024") == DataSize.ofKilobytes(1));
}

@("parseNegativeNumberWithNullDefaultUnitUsesBytes")
unittest
{
    // parseNegativeNumberWithNullDefaultUnitUsesBytes
    static assert(!__traits(compiles, DataSize.parse("-1024", null)));
    assert(DataSize.parse("-1024") == DataSize.ofKilobytes(-1));
}

@("parseWithCustomDefaultUnit")
unittest
{
    // parseWithCustomDefaultUnit
    assert(DataSize.parse("1", DataUnit.KILOBYTES) == DataSize.ofKilobytes(1));
}

@("parseNegativeNumberWithCustomDefaultUnit")
unittest
{
    // parseNegativeNumberWithCustomDefaultUnit
    assert(DataSize.parse("-1", DataUnit.KILOBYTES) == DataSize.ofKilobytes(-1));
}

@("parseWithBytes")
unittest
{
    // parseWithBytes
    foreach (text; ["1024B", "1024 B", "1024B   ", "   1024B", " 1024B ", "\t1024   B\t"])
        assert(DataSize.parse(text) == DataSize.ofKilobytes(1));
}

@("parseWithNegativeBytes")
unittest
{
    // parseWithNegativeBytes
    assert(DataSize.parse("-1024B") == DataSize.ofKilobytes(-1));
}

@("parseWithPositiveBytes")
unittest
{
    // parseWithPositiveBytes
    assert(DataSize.parse("+1024B") == DataSize.ofKilobytes(1));
}

@("parseWithKilobytes")
unittest
{
    // parseWithKilobytes
    assert(DataSize.parse("1KB") == DataSize.ofBytes(1024));
}

@("parseWithNegativeKilobytes")
unittest
{
    // parseWithNegativeKilobytes
    assert(DataSize.parse("-1KB") == DataSize.ofBytes(-1024));
}

@("parseWithMegabytes")
unittest
{
    // parseWithMegabytes
    assert(DataSize.parse("4MB") == DataSize.ofMegabytes(4));
}

@("parseWithNegativeMegabytes")
unittest
{
    // parseWithNegativeMegabytes
    assert(DataSize.parse("-4MB") == DataSize.ofMegabytes(-4));
}

@("parseWithGigabytes")
unittest
{
    // parseWithGigabytes
    assert(DataSize.parse("1GB") == DataSize.ofMegabytes(1024));
}

@("parseWithNegativeGigabytes")
unittest
{
    // parseWithNegativeGigabytes
    assert(DataSize.parse("-1GB") == DataSize.ofMegabytes(-1024));
}

@("parseWithTerabytes")
unittest
{
    // parseWithTerabytes
    assert(DataSize.parse("1TB") == DataSize.ofTerabytes(1));
}

@("parseWithNegativeTerabytes")
unittest
{
    // parseWithNegativeTerabytes
    assert(DataSize.parse("-1TB") == DataSize.ofTerabytes(-1));
}

@("isNegativeWithPositive")
unittest
{
    // isNegativeWithPositive
    assert(!DataSize.ofBytes(50).isNegative());
}

@("isNegativeWithZero")
unittest
{
    // isNegativeWithZero
    assert(!DataSize.ofBytes(0).isNegative());
}

@("isNegativeWithNegative")
unittest
{
    // isNegativeWithNegative
    assert(DataSize.ofBytes(-1).isNegative());
}

@("toStringUsesBytes")
unittest
{
    // toStringUsesBytes
    assert(DataSize.ofKilobytes(1).toString() == "1024B");
}

@("toStringWithNegativeBytes")
unittest
{
    // toStringWithNegativeBytes
    assert(DataSize.ofKilobytes(-1).toString() == "-1024B");
}

@("parseWithUnsupportedUnit")
unittest
{
    // parseWithUnsupportedUnit
    foreach (text; ["3WB", "3 WB"])
    {
        IllegalArgumentException failure;
        try
            DataSize.parse(text);
        catch (IllegalArgumentException e)
            failure = e;
        assert(failure !is null && failure.getMessage() == "'" ~ text ~ "' is not a valid data size");
        // The cause is the unknown suffix, as Java's DataUnit.fromSuffix reports it.
        assert(failure.getCause() !is null && failure.getCause().msg == "Unknown data unit suffix 'WB'");
    }
}

@("Flint: overflow, comparison, hashCode and an unknown suffix through fromSuffix")
unittest
{
    import flint.java.lang : ArithmeticException;
    import flint.util.unit : fromSuffix;

    bool overflowed;
    try
        DataSize.ofTerabytes(long.max);
    catch (ArithmeticException)
        overflowed = true;
    assert(overflowed);
    // An overflowing parse is a malformed data size whose cause is the arithmetic overflow, as in Spring.
    IllegalArgumentException parse;
    try
        DataSize.parse("9223372036854775807TB");
    catch (IllegalArgumentException e)
        parse = e;
    assert(parse !is null && cast(ArithmeticException) parse.getCause() !is null);
    assert(DataSize.ofKilobytes(1) > DataSize.ofBytes(1023) && DataSize.ofBytes(-1).compareTo(DataSize.ofBytes(0)) < 0);
    assert(DataSize.ofBytes(1L << 40).hashCode() == 256 && DataSize.ofBytes(-1).hashCode() == 0);
    assert(fromSuffix("MB") == DataUnit.MEGABYTES && DataSize.init == DataSize.ofBytes(0));
    // Suffixes are case-sensitive, as Spring's are.
    bool lower;
    try
        fromSuffix("kb");
    catch (IllegalArgumentException)
        lower = true;
    assert(lower);
}
