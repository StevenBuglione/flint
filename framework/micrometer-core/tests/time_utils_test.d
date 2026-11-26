module micrometer_time_utils_test;

import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument.util : TimeUtils;

@safe:

@("time unit conversions preserve fractional values without allocating")
unittest
{
    import std.math.traits : isNaN, signbit;

    () nothrow @nogc {
        assert(TimeUtils.nanosToUnit(2_500_000.0, TimeUnit.MILLISECONDS) == 2.5);
        assert(TimeUtils.microsToUnit(1.5, TimeUnit.NANOSECONDS) == 1_500.0);
        assert(TimeUtils.millisToUnit(1.5, TimeUnit.SECONDS) == 0.0015);
        assert(TimeUtils.secondsToUnit(1.5, TimeUnit.MILLISECONDS) == 1_500.0);
        assert(TimeUtils.minutesToUnit(1.5, TimeUnit.SECONDS) == 90);
        assert(TimeUtils.hoursToUnit(1.5, TimeUnit.MINUTES) == 90);
        assert(TimeUtils.daysToUnit(1.5, TimeUnit.HOURS) == 36);
        assert(TimeUtils.convert(double.max, TimeUnit.DAYS, TimeUnit.DAYS) == double.max);
        assert(TimeUtils.convert(-0.25, TimeUnit.DAYS, TimeUnit.MINUTES) == -360);
        assert(signbit(TimeUtils.convert(-0.0, TimeUnit.MICROSECONDS, TimeUnit.HOURS)));
        assert(isNaN(TimeUtils.convert(double.nan, TimeUnit.HOURS, TimeUnit.MILLISECONDS)));
    }();
}
