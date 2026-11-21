module flint.serde.json_visit_test;

import flint.arena : Error, Status;
import flint.serde.json_visit : JsonMemberName, visitJsonArray, visitJsonObject;

@safe:

unittest
{
    uint visited;
    auto inspect = delegate Error(scope JsonMemberName name, scope const(ubyte)[] encoded) @safe nothrow @nogc {
        ++visited;
        assert(name.isName("id") && name.length == 2);
        ubyte[2] key;
        assert(name.copyName(key[]) && key[] == cast(const(ubyte)[]) "id");
        const walked = visitJsonArray(encoded, (scope const(ubyte)[] item) {
            assert(item == cast(const(ubyte)[]) "true");
            return Error.init;
        });
        return walked;
    };
    assert(visitJsonObject(cast(const(ubyte)[]) "{\"i\\u0064\": [true]}", inspect).code == Status.ok);
    assert(visited == 1);
    assert(visitJsonObject(cast(const(ubyte)[]) "{\"id\":[],\"i\\u0064\":[]}", inspect).code == Status.invalidArgument);
    const nested = cast(const(ubyte)[]) "{\"id\":[{\"a\":0,\"a\":1}]}";
    assert(visitJsonObject(nested, inspect).code == Status.invalidArgument);
    assert(visitJsonObject(cast(const(ubyte)[]) "{\"id\":[true]} false", inspect).code == Status.invalidArgument);
    assert(visited == 1);
}
