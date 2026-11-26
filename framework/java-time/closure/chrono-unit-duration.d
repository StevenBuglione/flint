module app;

import flint.java.time.temporal.chronounit : ChronoUnit, getDuration, isDateBased, isDurationEstimated, isTimeBased;

@safe:

int main(string[] args)
{
    const unit = cast(ChronoUnit)(args.length % (cast(size_t) ChronoUnit.max + 1));
    const duration = unit.getDuration();
    const seconds = cast(ulong) duration.getSeconds();
    const flags = (unit.isDateBased() ? 1 : 0) | (unit.isTimeBased() ? 2 : 0) | (unit.isDurationEstimated() ? 4 : 0);
    return cast(int)(seconds ^ (seconds >> 32)) + duration.getNano() + flags;
}
