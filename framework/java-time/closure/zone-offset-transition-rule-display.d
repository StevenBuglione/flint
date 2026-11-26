module app;

import flint.java.time.zone.zoneoffsettransitionrule : ZoneOffsetTransitionRule;

@safe:

int main(string[] args)
{
    const reference = ZoneOffsetTransitionRule.init;
    const day = args.length % 2 != 0 ? -2 : 29;
    const rule = ZoneOffsetTransitionRule.of(reference.getMonth(), day, reference.getDayOfWeek(),
            reference.getLocalTime(), args.length > 2, reference.getTimeDefinition(),
            reference.getStandardOffset(), reference.getOffsetBefore(), reference.getOffsetAfter());
    const display = rule.toString();
    return display[args.length % display.length] & 127;
}
