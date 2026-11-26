module app;

import flint.java.time.zone.zonerules : ZoneRules;
import std.traits : Parameters;

@safe:

int main(string[] args)
{
    alias Offset = Parameters!(ZoneRules.of)[0];
    const offset = Offset.ofTotalSeconds(cast(int)(args.length % 64_800));
    const display = ZoneRules.of(offset).toString();
    return display[args.length % display.length] & 127;
}
