module app;

import flint.java.time.zone.zoneoffsettransitionrule : valueOf, values;

@safe:

int main(string[] args)
{
    const definitions = values();
    const name = args.length > 1 ? args[1] : "WALL";
    return cast(int)(definitions[args.length % definitions.length] == valueOf(name));
}
