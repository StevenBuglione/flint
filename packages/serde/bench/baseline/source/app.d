/// Direct arena dependency control for the Serde size and fixture protocol.
module app;

import flint.arena : RequestArena, Status;
import serde_probe : Observation, fixtureSizes, measure, observe, payload, payloadFields, schema;

@safe:

private Observation copyFixture(ref scope RequestArena arena, scope const(ubyte)[] content) nothrow @nogc
{
    const result = arena.copyIn(content);
    if (!result.ok())
        return Observation.init;
    const observed = observe(arena, result.value, content);
    return arena.reset() == Status.ok ? observed : Observation.init;
}

/// Exercise the common dependency closure with the same observable fixtures.
int main()
{
    ubyte[65_536] backing;
    foreach (size; fixtureSizes)
    {
        foreach (escaped; [false, true])
        {
            scope arena = RequestArena(backing[]);
            const input = payload(size, escaped);
            const label = escaped ? "escaped" : "plain";
            if (!measure(label, size, payloadFields, () => copyFixture(arena, input)))
                return 1;
        }
    }
    foreach (fields; [8, 32, 128])
    {
        scope arena = RequestArena(backing[]);
        const expected = cast(const(ubyte)[]) schema(fields);
        if (!measure("schema", expected.length, fields, () => copyFixture(arena, expected)))
            return 1;
    }
    return 0;
}
