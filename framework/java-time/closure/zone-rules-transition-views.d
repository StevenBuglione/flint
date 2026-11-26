module app;

import flint.java.time.zone.zonerules : ZoneRules;
import std.traits : Parameters;

@safe:

int main(string[] args)
{
    alias Offset = Parameters!(ZoneRules.of)[0];
    alias Instant = Parameters!(ZoneRules.getStandardOffset)[0];
    const rules = ZoneRules.of(Offset.ofTotalSeconds(cast(int)(args.length % 64_800)));
    const instant = Instant.ofEpochSecond(args.length);
    auto next = rules.nextTransition(instant);
    auto prev = rules.previousTransition(instant);
    auto historic = rules.getTransitions();
    auto recurring = rules.getTransitionRules();
    return historic.size() + recurring.size() + next.isNull + prev.isNull;
}
