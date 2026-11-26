module app;

import flint.java.time.zone.zonerules : ZoneRules;
import std.traits : Parameters;
import std.typecons : Nullable;

@safe:

int main(string[] args)
{
    alias Offset = Parameters!(ZoneRules.of)[0];
    alias Instant = Parameters!(ZoneRules.getStandardOffset)[0];
    alias LocalDateTime = Parameters!(ZoneRules.isValidOffset)[0];
    const rules = ZoneRules.of(Offset.ofTotalSeconds(cast(int)(args.length % 64_800)));
    const instant = Instant.ofEpochSecond(args.length);
    const next = rules.nextTransition(Nullable!Instant(instant)).isNull;
    const previous = rules.previousTransition(instant).isNull;
    const local = rules.getTransition(Nullable!LocalDateTime.init).isNull;
    return (rules.getOffset(instant).getTotalSeconds() + next + previous + local) & 127;
}
