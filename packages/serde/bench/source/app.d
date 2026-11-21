/// Real monomorphic JSON and schema producer across three fixed input shapes.
module app;

import flint.arena : RequestArena, Status, Text;
import flint.serde : decodeInto, encodeJson, jsonSchema;
import serde_probe : Observation, fixtureSizes, measure, observe, payload, payloadFields, schema;

@safe:

private struct Payload
{
    uint code;
    Text text;
    bool ready;
}

private Observation roundTrip(ref scope RequestArena arena, scope const(ubyte)[] input) nothrow @nogc
{
    Payload value;
    const failure = decodeInto(input, value, arena);
    if (failure.code != Status.ok || value.code != 17 || !value.ready)
        return Observation.init;
    const result = encodeJson(value, arena);
    if (!result.ok())
        return Observation.init;
    const observed = observe(arena, result.value, input);
    return arena.reset() == Status.ok ? observed : Observation.init;
}

private Observation emitSchema(T)(ref scope RequestArena arena, scope const(ubyte)[] expected) nothrow @nogc
{
    const result = jsonSchema!T(arena);
    if (!result.ok())
        return Observation.init;
    const observed = observe(arena, result.value, expected);
    return arena.reset() == Status.ok ? observed : Observation.init;
}

private bool measureSchema(T)(scope ubyte[] backing, size_t fields)
{
    scope arena = RequestArena(backing);
    const expected = cast(const(ubyte)[]) schema(fields);
    return measure("schema", expected.length, fields, () => emitSchema!T(arena, expected));
}

/// Return failure on an invalid fixture, even with assertions compiled out.
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
            if (!measure(label, size, payloadFields, () => roundTrip(arena, input)))
                return 1;
        }
    }
    return measureSchema!Shape8(backing[], 8) && measureSchema!Shape32(backing[], 32)
        && measureSchema!Shape128(backing[], 128) ? 0 : 1;
}

private struct Shape8
{
    uint field001;
    uint field002;
    uint field003;
    uint field004;
    uint field005;
    uint field006;
    uint field007;
    uint field008;
}

private struct Shape32
{
    uint field001;
    uint field002;
    uint field003;
    uint field004;
    uint field005;
    uint field006;
    uint field007;
    uint field008;
    uint field009;
    uint field010;
    uint field011;
    uint field012;
    uint field013;
    uint field014;
    uint field015;
    uint field016;
    uint field017;
    uint field018;
    uint field019;
    uint field020;
    uint field021;
    uint field022;
    uint field023;
    uint field024;
    uint field025;
    uint field026;
    uint field027;
    uint field028;
    uint field029;
    uint field030;
    uint field031;
    uint field032;
}

private struct Shape128
{
    uint field001;
    uint field002;
    uint field003;
    uint field004;
    uint field005;
    uint field006;
    uint field007;
    uint field008;
    uint field009;
    uint field010;
    uint field011;
    uint field012;
    uint field013;
    uint field014;
    uint field015;
    uint field016;
    uint field017;
    uint field018;
    uint field019;
    uint field020;
    uint field021;
    uint field022;
    uint field023;
    uint field024;
    uint field025;
    uint field026;
    uint field027;
    uint field028;
    uint field029;
    uint field030;
    uint field031;
    uint field032;
    uint field033;
    uint field034;
    uint field035;
    uint field036;
    uint field037;
    uint field038;
    uint field039;
    uint field040;
    uint field041;
    uint field042;
    uint field043;
    uint field044;
    uint field045;
    uint field046;
    uint field047;
    uint field048;
    uint field049;
    uint field050;
    uint field051;
    uint field052;
    uint field053;
    uint field054;
    uint field055;
    uint field056;
    uint field057;
    uint field058;
    uint field059;
    uint field060;
    uint field061;
    uint field062;
    uint field063;
    uint field064;
    uint field065;
    uint field066;
    uint field067;
    uint field068;
    uint field069;
    uint field070;
    uint field071;
    uint field072;
    uint field073;
    uint field074;
    uint field075;
    uint field076;
    uint field077;
    uint field078;
    uint field079;
    uint field080;
    uint field081;
    uint field082;
    uint field083;
    uint field084;
    uint field085;
    uint field086;
    uint field087;
    uint field088;
    uint field089;
    uint field090;
    uint field091;
    uint field092;
    uint field093;
    uint field094;
    uint field095;
    uint field096;
    uint field097;
    uint field098;
    uint field099;
    uint field100;
    uint field101;
    uint field102;
    uint field103;
    uint field104;
    uint field105;
    uint field106;
    uint field107;
    uint field108;
    uint field109;
    uint field110;
    uint field111;
    uint field112;
    uint field113;
    uint field114;
    uint field115;
    uint field116;
    uint field117;
    uint field118;
    uint field119;
    uint field120;
    uint field121;
    uint field122;
    uint field123;
    uint field124;
    uint field125;
    uint field126;
    uint field127;
    uint field128;
}
