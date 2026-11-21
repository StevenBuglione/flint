module flint.serde.json_visit_test;

import flint.arena : Error, Status;
import flint.serde : DecodeOptions;
import flint.serde.json_visit : JsonMemberName, visitJsonArray, visitJsonObject, visitJsonObjectRanges;

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

unittest
{
    enum cap = 4 * 1024 * 1024;
    auto document = new ubyte[cap + 1];
    document[] = ' ';
    enum member = `{"i\u0064": [true]}`;
    document[0 .. member.length] = cast(const(ubyte)[]) member;
    DecodeOptions bounds;
    bounds.maxBytes = cap;
    uint seen;
    auto inspect = delegate Error(scope JsonMemberName key, size_t offset, size_t length) @safe nothrow @nogc {
        ++seen;
        assert(key.isName("id"));
        assert(offset == 12 && length == 6);
        assert(document[offset .. offset + length] == cast(const(ubyte)[]) "[true]");
        return Error.init;
    };
    assert(visitJsonObjectRanges(document[0 .. cap], inspect, bounds).code == Status.ok);
    assert(seen == 1);
    assert(visitJsonObjectRanges(document, inspect, bounds).code == Status.resourceExhausted);
    assert(visitJsonObjectRanges(document[0 .. cap], inspect).code == Status.resourceExhausted);
    document[cap - 1] = 'x';
    assert(visitJsonObjectRanges(document[0 .. cap], inspect, bounds).code == Status.invalidArgument);
    const duplicate = cast(const(ubyte)[]) `{"id":[true],"i\u0064":[]}`;
    assert(visitJsonObjectRanges(duplicate, inspect, bounds).code == Status.invalidArgument);
    assert(seen == 1);
}
