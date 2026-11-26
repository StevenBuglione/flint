module app;

import flint.java.time.zone.zonerules : ZoneRules;
import std.traits : Parameters;
import std.typecons : Nullable;

@safe:

int main(string[] args)
{
    alias Offset = Parameters!(ZoneRules.of)[0];
    alias LocalDateTime = Parameters!(ZoneRules.isValidOffset)[0];
    const offset = Offset.ofTotalSeconds(cast(int)(args.length % 64_800));
    const rules = ZoneRules.of(offset);
    const date = args.length > 1 ? Nullable!LocalDateTime(LocalDateTime.init) : Nullable!LocalDateTime.init;
    auto valid = rules.getValidOffsets(date);
    return valid.get(0).getTotalSeconds() & 127;
}
