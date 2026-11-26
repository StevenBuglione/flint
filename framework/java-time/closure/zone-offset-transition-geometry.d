module app;

import flint.java.time.zone.zoneoffsettransition : ZoneOffsetTransition;
import std.typecons : Nullable;

@safe:

int main(string[] args)
{
    const reference = ZoneOffsetTransition.init;
    const time = reference.getDateTimeBefore().plusSeconds(cast(long) args.length);
    auto before = reference.getOffsetBefore();
    const after = reference.getOffsetAfter();
    const gap = ZoneOffsetTransition.of(time, before, after);
    const overlap = ZoneOffsetTransition.of(time, after, before);
    const transition = args.length > 1 ? overlap : gap;
    const valid = transition.isValidOffset(Nullable!(typeof(before))(before));
    const duration = transition.getDuration().getSeconds();
    const instant = transition.getInstant().getEpochSecond();
    const nextDay = transition.getDateTimeAfter().getDayOfMonth();
    return cast(int)(duration + instant + nextDay + transition.hashCode() + valid) & 127;
}
