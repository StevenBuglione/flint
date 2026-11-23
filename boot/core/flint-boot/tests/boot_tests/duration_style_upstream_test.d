// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/convert/
// DurationStyleTests.java: the tests boot_tests/binder_test.d does not port (it holds
// detectAndParseWhenBadFormatShouldThrowException).
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `DurationStyle.detectAndParse(value, unit)` is the binder's
// `parseDuration(value, suffix)` with the unit's simple suffix (`ChronoUnit.SECONDS` is `"s"`); `java.time.Duration`
// is `core.time.Duration`; AssertJ's `hasNanos`/`hasMillis`/... are `total!"nsecs"`/`total!"msecs"`/...; a
// @ParameterizedTest loops over its values.
// Not ported: detectAndParseWhenValueIsNullShouldThrowException (a null D string is the empty string).
module boot_tests.duration_style_upstream_test;

import core.time : Duration, days, hours, minutes, msecs, seconds;
import flint.boot.context.properties.bind : parseDuration;

@safe:

private Duration iso(string text)
{
    // java.time.Duration.parse of the upstream expectations, written out.
    switch (text)
    {
    case "pt20.345s":
    case "PT20.345S":
        return msecs(20_345);
    case "PT15M":
        return minutes(15);
    case "PT10H":
        return hours(10);
    case "P2D":
        return days(2);
    case "P2DT3H4M":
        return days(2) + hours(3) + minutes(4);
    case "-PT6H3M":
        return -(hours(6) + minutes(3));
    case "-PT-6H+3M":
        return hours(5) + minutes(57);
    default:
        assert(false, text);
    }
}

@("detectAndParseWhenIso8601ShouldReturnDuration") unittest
{
    assert(parseDuration("pt20.345s") == iso("pt20.345s"));
    assert(parseDuration("PT20.345S") == iso("PT20.345S"));
    assert(parseDuration("PT15M") == iso("PT15M"));
    assert(parseDuration("+PT15M") == iso("PT15M"));
    assert(parseDuration("PT10H") == iso("PT10H"));
    assert(parseDuration("P2D") == iso("P2D"));
    assert(parseDuration("P2DT3H4M") == iso("P2DT3H4M"));
    assert(parseDuration("-PT6H3M") == iso("-PT6H3M"));
    assert(parseDuration("-PT-6H+3M") == iso("-PT-6H+3M"));
}

version (FlintNanosecondDurations)
{
    // Gap: core.time.Duration counts in 100 ns units, so "10ns" parses to a zero duration.
    @("detectAndParseWhenSimpleNanosShouldReturnDuration") unittest
    {
        assert(parseDuration("10ns").total!"nsecs" == 10);
        assert(parseDuration("10NS").total!"nsecs" == 10);
        assert(parseDuration("+10ns").total!"nsecs" == 10);
        assert(parseDuration("-10ns").total!"nsecs" == -10);
    }
}

@("detectAndParseWhenSimpleMicrosShouldReturnDuration") unittest
{
    assert(parseDuration("10us").total!"nsecs" == 10_000);
    assert(parseDuration("10US").total!"nsecs" == 10_000);
    assert(parseDuration("+10us").total!"nsecs" == 10_000);
    assert(parseDuration("-10us").total!"nsecs" == -10_000);
}

@("detectAndParseWhenSimpleMillisShouldReturnDuration") unittest
{
    assert(parseDuration("10ms").total!"msecs" == 10);
    assert(parseDuration("10MS").total!"msecs" == 10);
    assert(parseDuration("+10ms").total!"msecs" == 10);
    assert(parseDuration("-10ms").total!"msecs" == -10);
}

@("detectAndParseWhenSimpleSecondsShouldReturnDuration") unittest
{
    assert(parseDuration("10s").total!"seconds" == 10);
    assert(parseDuration("10S").total!"seconds" == 10);
    assert(parseDuration("+10s").total!"seconds" == 10);
    assert(parseDuration("-10s").total!"seconds" == -10);
}

@("detectAndParseWhenSimpleMinutesShouldReturnDuration") unittest
{
    assert(parseDuration("10m").total!"minutes" == 10);
    assert(parseDuration("10M").total!"minutes" == 10);
    assert(parseDuration("+10m").total!"minutes" == 10);
    assert(parseDuration("-10m").total!"minutes" == -10);
}

@("detectAndParseWhenSimpleHoursShouldReturnDuration") unittest
{
    assert(parseDuration("10h").total!"hours" == 10);
    assert(parseDuration("10H").total!"hours" == 10);
    assert(parseDuration("+10h").total!"hours" == 10);
    assert(parseDuration("-10h").total!"hours" == -10);
}

@("detectAndParseWhenSimpleDaysShouldReturnDuration") unittest
{
    assert(parseDuration("10d").total!"days" == 10);
    assert(parseDuration("10D").total!"days" == 10);
    assert(parseDuration("+10d").total!"days" == 10);
    assert(parseDuration("-10d").total!"days" == -10);
}

@("detectAndParseWhenSimpleWithoutSuffixShouldReturnDuration") unittest
{
    assert(parseDuration("10").total!"msecs" == 10);
    assert(parseDuration("+10").total!"msecs" == 10);
    assert(parseDuration("-10").total!"msecs" == -10);
}

@("detectAndParseWhenSimpleWithoutSuffixButWithChronoUnitShouldReturnDuration") unittest
{
    assert(parseDuration("10", "s").total!"seconds" == 10);
    assert(parseDuration("+10", "s").total!"seconds" == 10);
    assert(parseDuration("-10", "s").total!"seconds" == -10);
}

version (FlintDurationStyleApi)
{
    // Gap: DurationStyle itself (detect, a style's own parse and print) is not ported; only detectAndParse is.
    import boot_tests.support : assertThrows;
    import core.time : nsecs, usecs;
    import flint.boot.convert : ChronoUnit, DurationStyle, parse, print;
    import flint.java.lang : ArithmeticException, IllegalArgumentException;

    @("detectWhenSimpleShouldReturnSimple") unittest
    {
        foreach (text; [
            "10", "+10", "-10", "10ns", "10ms", "10s", "10m", "10h", "10d", "-10ms", "-10ms", "10D"
        ])
            assert(DurationStyle.detect(text) == DurationStyle.SIMPLE);
    }

    @("detectWhenIso8601ShouldReturnIso8601") unittest
    {
        foreach (text; [
            "pt20.345s", "PT20.345S", "PT15M", "+PT15M", "PT10H", "P2D", "P2DT3H4M", "-PT6H3M",
            "-PT-6H+3M"
        ])
            assert(DurationStyle.detect(text) == DurationStyle.ISO8601);
    }

    @("detectWhenUnknownShouldThrowException") unittest
    {
        assertThrows!IllegalArgumentException(() { DurationStyle.detect("bad"); }, "'bad' is not a valid duration");
    }

    @("parseIso8601ShouldParse") unittest
    {
        assert(parse(DurationStyle.ISO8601, "pt20.345s") == iso("pt20.345s"));
        assert(parse(DurationStyle.ISO8601, "PT20.345S") == iso("PT20.345S"));
        assert(parse(DurationStyle.ISO8601, "PT15M") == iso("PT15M"));
        assert(parse(DurationStyle.ISO8601, "+PT15M") == iso("PT15M"));
        assert(parse(DurationStyle.ISO8601, "PT10H") == iso("PT10H"));
        assert(parse(DurationStyle.ISO8601, "P2D") == iso("P2D"));
        assert(parse(DurationStyle.ISO8601, "P2DT3H4M") == iso("P2DT3H4M"));
        assert(parse(DurationStyle.ISO8601, "-PT6H3M") == iso("-PT6H3M"));
        assert(parse(DurationStyle.ISO8601, "-PT-6H+3M") == iso("-PT-6H+3M"));
    }

    @("parseIso8601WithUnitShouldIgnoreUnit") unittest
    {
        assert(parse(DurationStyle.ISO8601, "pt20.345s", ChronoUnit.SECONDS) == iso("pt20.345s"));
        assert(parse(DurationStyle.ISO8601, "PT20.345S", ChronoUnit.SECONDS) == iso("PT20.345S"));
        assert(parse(DurationStyle.ISO8601, "PT15M", ChronoUnit.SECONDS) == iso("PT15M"));
        assert(parse(DurationStyle.ISO8601, "+PT15M", ChronoUnit.SECONDS) == iso("PT15M"));
        assert(parse(DurationStyle.ISO8601, "PT10H", ChronoUnit.SECONDS) == iso("PT10H"));
        assert(parse(DurationStyle.ISO8601, "P2D") == iso("P2D"));
        assert(parse(DurationStyle.ISO8601, "P2DT3H4M", ChronoUnit.SECONDS) == iso("P2DT3H4M"));
        assert(parse(DurationStyle.ISO8601, "-PT6H3M", ChronoUnit.SECONDS) == iso("-PT6H3M"));
        assert(parse(DurationStyle.ISO8601, "-PT-6H+3M", ChronoUnit.SECONDS) == iso("-PT-6H+3M"));
    }

    @("parseIso8601WhenSimpleShouldThrowException") unittest
    {
        assertThrows!IllegalArgumentException(() { parse(DurationStyle.ISO8601, "10d"); },
                "'10d' is not a valid ISO-8601 duration");
    }

    @("parseSimpleShouldParse") unittest
    {
        assert(parse(DurationStyle.SIMPLE, "10m").total!"minutes" == 10);
    }

    @("parseSimpleWithUnitShouldUseUnitAsFallback") unittest
    {
        assert(parse(DurationStyle.SIMPLE, "10m", ChronoUnit.SECONDS).total!"minutes" == 10);
        assert(parse(DurationStyle.SIMPLE, "10", ChronoUnit.MINUTES).total!"minutes" == 10);
    }

    @("parseSimpleWhenUnknownUnitShouldThrowException") unittest
    {
        try
        {
            parse(DurationStyle.SIMPLE, "10mb");
            assert(false, "expected an IllegalArgumentException");
        }
        catch (IllegalArgumentException ex)
        {
            assert(ex.next !is null);
            assert(ex.next.msg == "Unknown unit 'mb'");
        }
    }

    @("parseSimpleWhenIso8601ShouldThrowException") unittest
    {
        assertThrows!IllegalArgumentException(() { parse(DurationStyle.SIMPLE, "PT10H"); },
                "'PT10H' is not a valid simple duration");
    }

    @("printIso8601ShouldPrint") unittest
    {
        assert(print(DurationStyle.ISO8601, iso("-PT-6H+3M")) == "PT5H57M");
    }

    @("printIso8601ShouldIgnoreUnit") unittest
    {
        assert(print(DurationStyle.ISO8601, iso("-PT-6H+3M"), ChronoUnit.DAYS) == "PT5H57M");
    }

    @("printSimpleWithoutUnitShouldPrintInMs") unittest
    {
        assert(print(DurationStyle.SIMPLE, seconds(1)) == "1000ms");
    }

    @("printSimpleWithSecondsUnitShouldPrintInUnit") unittest
    {
        assert(print(DurationStyle.SIMPLE, msecs(1000), ChronoUnit.SECONDS) == "1s");
    }

    @("printSimpleWithMicrosUnitShouldPrintInUnit") unittest
    {
        assert(print(DurationStyle.SIMPLE, nsecs(2000), ChronoUnit.MICROS) == "2us");
    }

    @("printSimpleWithMicrosUnitShouldSupportFullLongRange") unittest
    {
        import std.conv : to;

        foreach (micros; [long.min, long.max])
        {
            const duration = usecs(micros);
            assert(print(DurationStyle.SIMPLE, duration, ChronoUnit.MICROS) == micros.to!string ~ "us");
            const withFraction = duration + nsecs(micros < 0 ? -999 : 999);
            assert(print(DurationStyle.SIMPLE, withFraction, ChronoUnit.MICROS) == micros.to!string ~ "us");
        }
    }

    @("printSimpleWithMicrosUnitWhenResultOverflowsShouldThrowException") unittest
    {
        foreach (micros; [long.min, long.max])
        {
            const duration = usecs(micros) + nsecs(micros < 0 ? -1000 : 1000);
            assertThrows!ArithmeticException(() {
                print(DurationStyle.SIMPLE, duration, ChronoUnit.MICROS);
            });
        }
    }

    @("printSimpleWithMicrosUnitShouldTruncateTowardsZero") unittest
    {
        import std.conv : to;

        foreach (nanos; [-1999L, -1001, -999, 0, 999, 1001, 1999])
            assert(print(DurationStyle.SIMPLE, nsecs(nanos), ChronoUnit.MICROS) == (nanos / 1000).to!string ~ "us");
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
