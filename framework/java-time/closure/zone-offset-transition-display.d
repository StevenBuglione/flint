module app;

import flint.java.time.zone.zoneoffsettransition : ZoneOffsetTransition;

@safe:

int main(string[] args)
{
    const reference = ZoneOffsetTransition.init;
    const time = reference.getDateTimeBefore().plusSeconds(cast(long) args.length);
    const before = reference.getOffsetBefore();
    const after = reference.getOffsetAfter();
    const transition = args.length > 1 ? ZoneOffsetTransition.of(time, after,
            before) : ZoneOffsetTransition.of(time, before, after);
    const display = transition.toString();
    return display[args.length % display.length] & 127;
}
