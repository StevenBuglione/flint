module flint.java.time.temporal_metadata_test;

import core.memory : GC;
import flint.java.time.temporal.chronofield : ChronoField, getBaseUnit, getRangeUnit;
import flint.java.time.temporal.chronounit : ChronoUnit, getDuration, isDateBased,
    isDurationEstimated, isTimeBased, toString;

@safe:

@("chrono units and field unit pairs match Java without allocating") unittest
{
    const before = GC.stats().allocatedInCurrentThread;
    assert(cast(int) ChronoUnit.NANOS == 0 && cast(int) ChronoUnit.FOREVER == 15);
    const micros = ChronoUnit.MICROS.getDuration();
    assert(micros.getSeconds() == 0 && micros.getNano() == 1_000);
    assert(ChronoUnit.MICROS.isTimeBased() && !ChronoUnit.MICROS.isDurationEstimated());
    const month = ChronoUnit.MONTHS.getDuration();
    assert(month.getSeconds() == 2_629_746 && month.getNano() == 0);
    assert(ChronoUnit.MONTHS.isDateBased() && ChronoUnit.MONTHS.isDurationEstimated());
    const forever = ChronoUnit.FOREVER.getDuration();
    assert(forever.getSeconds() == long.max && forever.getNano() == 999_999_999);
    assert(!ChronoUnit.FOREVER.isDateBased() && !ChronoUnit.FOREVER.isTimeBased());
    assert(ChronoUnit.FOREVER.isDurationEstimated() && ChronoUnit.HALF_DAYS.toString() == "HalfDays");
    assert(ChronoField.DAY_OF_MONTH.getBaseUnit() == ChronoUnit.DAYS);
    assert(ChronoField.DAY_OF_MONTH.getRangeUnit() == ChronoUnit.MONTHS);
    assert(ChronoField.INSTANT_SECONDS.getRangeUnit() == ChronoUnit.FOREVER);
    assert(GC.stats().allocatedInCurrentThread == before);
}
