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
    const offset = Offset.ofTotalSeconds(cast(int)(args.length % 64_800));
    const rules = ZoneRules.of(offset);
    const instant = Instant.ofEpochSecond(args.length);
    const atInstant = rules.getOffset(instant);
    const standard = rules.getStandardOffset(Nullable!Instant.init);
    const valid = rules.isValidOffset(Nullable!LocalDateTime.init, offset);
    const savings = rules.getDaylightSavings(instant).getSeconds();
    return cast(int)(atInstant.getTotalSeconds() + standard.getTotalSeconds() + savings + valid) & 127;
}
