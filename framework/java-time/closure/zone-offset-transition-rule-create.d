module app;

import flint.java.time.zone.zoneoffsettransitionrule : ZoneOffsetTransitionRule;

@safe:

int main(string[] args)
{
    const reference = ZoneOffsetTransitionRule.init;
    const year = 1970 + cast(int)(args.length % 137);
    auto weekday = reference.getDayOfWeek();
    if (args.length > 1)
        weekday = reference.createTransition(year).getDateTimeBefore().getDayOfWeek();
    const day = args.length % 2 != 0 ? -2 : 29;
    const definition = args.length > 2 ? ZoneOffsetTransitionRule.TimeDefinition.UTC : reference.getTimeDefinition();
    const rule = ZoneOffsetTransitionRule.of(reference.getMonth(), day, weekday, reference.getLocalTime(),
            false, definition, reference.getStandardOffset(), reference.getOffsetBefore(), reference.getOffsetAfter());
    const transition = rule.createTransition(year);
    return cast(int)(transition.toEpochSecond() + transition.hashCode() + rule.hashCode()) & 127;
}
