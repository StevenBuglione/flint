module flint.java.time.chrono_field_test;

import core.memory : GC;
import flint.java.time.temporal.chronofield : ChronoField, isDateBased, isTimeBased, range, toString;

@safe:

@("chrono fields keep Java declaration order and allocation-free metadata") unittest
{
    const before = GC.stats().allocatedInCurrentThread;
    assert(cast(int) ChronoField.NANO_OF_SECOND == 0);
    assert(cast(int) ChronoField.DAY_OF_MONTH == 18);
    assert(cast(int) ChronoField.OFFSET_SECONDS == 29);

    const nanos = ChronoField.NANO_OF_DAY.range();
    assert(nanos.isFixed() && nanos.getMaximum() == 86_399_999_999_999);
    assert(ChronoField.NANO_OF_DAY.isTimeBased() && !ChronoField.NANO_OF_DAY.isDateBased());

    const days = ChronoField.DAY_OF_MONTH.range();
    assert(!days.isFixed() && days.getSmallestMaximum() == 28 && days.getMaximum() == 31);
    assert(ChronoField.DAY_OF_MONTH.isDateBased() && !ChronoField.DAY_OF_MONTH.isTimeBased());
    assert(ChronoField.DAY_OF_MONTH.toString() == "DayOfMonth");

    const epoch = ChronoField.EPOCH_DAY.range();
    assert(epoch.getMinimum() == -365_243_219_162 && epoch.getMaximum() == 365_241_780_471);
    const instant = ChronoField.INSTANT_SECONDS.range();
    assert(instant.getMinimum() == long.min && instant.getMaximum() == long.max);
    assert(!ChronoField.INSTANT_SECONDS.isDateBased() && !ChronoField.INSTANT_SECONDS.isTimeBased());
    assert(!ChronoField.OFFSET_SECONDS.isDateBased() && !ChronoField.OFFSET_SECONDS.isTimeBased());
    assert(GC.stats().allocatedInCurrentThread == before);
}
