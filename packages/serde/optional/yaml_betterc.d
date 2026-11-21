/// Link and execute the optional pinned YAML profile without the D runtime.
module yaml_betterc;

import flint.arena : RequestArena, Status, Text;
import flint.serde.yaml : decodeYamlInto, encodeYaml;

@safe:

private struct Payload
{
    Text name;
    uint size;
}

extern (C) int main() nothrow @nogc
{
    ubyte[256] storage;
    scope arena = RequestArena(storage[]);
    Payload payload;

    enum source = "name: 'libyaml'\nsize: 42\n";
    assert(decodeYamlInto(cast(const(ubyte)[]) source, payload, arena).code == Status.ok);
    assert(payload.size == 42);
    const serialized = encodeYaml(payload, arena);
    assert(serialized.ok());
    const read = arena.read(serialized.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        enum expected = `{"name":"libyaml","size":42}`;
        assert(bytes.length == expected.length);
        foreach (index, byteValue; bytes)
            assert(byteValue == expected[index]);
    });
    assert(read == Status.ok);
    return 0;
}
