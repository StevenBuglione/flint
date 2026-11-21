/// Scoped native provider tests and explicit unavailable behavior.
module yaml_behavior;

import flint.arena : RequestArena, Status, Text;
import flint.serde : DecodeOptions, UnknownFields;
import flint.serde.yaml : decodeYamlInto, encodeYaml;

@safe:

private struct Payload
{
    Text name;
    ushort port;
    int[2] values;
}

version (FlintNativeLibyaml)
{
    @("pinned libyaml parses block data into independent arena strings")
    unittest
    {
        ubyte[1024] storage;
        scope arena = RequestArena(storage[]);
        Payload payload;
        enum data = "name: !!str 12\nport: 08080\nvalues: [0xA, -2]\n";
        char[data.length] input = data;
        auto failure = decodeYamlInto(cast(const(ubyte)[]) input[], payload, arena);
        assert(failure.code == Status.ok, failure.message);
        assert(payload.port == 8080 && payload.values[0] == 10 && payload.values[1] == -2);

        input[] = '!';
        const read = arena.read(payload.name.bytes, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            assert(bytes.length == 2 && bytes[0] == '1' && bytes[1] == '2');
        });
        assert(read == Status.ok);

        auto output = encodeYaml(payload, arena);
        assert(output.ok());
        const reread = arena.read(output.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            Payload roundtrip;
            assert(decodeYamlInto(bytes, roundtrip, arena).code == Status.ok);
            assert(roundtrip.port == payload.port && roundtrip.values[0] == payload.values[0]);
        });
        assert(reread == Status.ok);
    }

    @("pinned libyaml rejects unsafe features and duplicate keys before materialization")
    unittest
    {
        ubyte[128] storage;
        scope arena = RequestArena(storage[]);
        Payload payload;
        payload.port = 91;
        const prior = arena.copyIn(cast(const(ubyte)[]) "preserved");
        assert(prior.ok());
        payload.name = Text(prior.value);
        const used = arena.stats().used;

        auto options = DecodeOptions.init;
        options.unknownFields = UnknownFields.ignore;
        options.rejectDuplicateKeys = false;

        immutable denied = [
            "name: &anchor text\nport: 3\n", "name: *missing\nport: 3\n",
            "name: !application object\n", "name: 'é'\n'name': duplicate\n",
            "name: text\n---\nport: 41\n", "? [1, 2]\n: scalar\n",
            "name: text\nextra: {x: 1, 'x': 2}\n", "name: text\nport: [\n",
            "name: text\nport: 65536\n",
        ];
        foreach (source; denied)
        {
            const error = decodeYamlInto(cast(const(ubyte)[]) source, payload, arena, options);
            assert(error.code == Status.invalidArgument, source);
            assert(error.offset <= source.length);
            assert(payload.port == 91);
            assert(payload.name.bytes == prior.value);
            assert(arena.stats().used == used);
        }

        enum duplicated = "name: 'é'\n'name': duplicate\n";
        const duplicate = decodeYamlInto(cast(const(ubyte)[]) duplicated, payload, arena, options);
        assert(duplicate.offset == "name: 'é'\n".length);
    }

    @("seeded malformed YAML events preserve arena ownership through provider cleanup")
    unittest
    {
        enum sample = "name: old\nport: 8080\nvalues: [7, -3]\n";
        uint state = 0x9108_b2aa;
        foreach (index; 0 .. 256)
        {
            ubyte[128] storage;
            scope arena = RequestArena(storage[]);
            const prior = arena.copyIn(cast(const(ubyte)[]) "saved");
            assert(prior.ok());
            Payload value = Payload(Text(prior.value), 17, [1, 2]);
            const used = arena.stats().used;

            ubyte[sample.length] source;
            source[] = cast(const(ubyte)[]) sample;
            state ^= state << 13;
            state ^= state >>> 17;
            state ^= state << 5;
            source[state % source.length] = cast(ubyte)(state >> 17);
            const failure = decodeYamlInto(source[], value, arena);
            if (failure.code != Status.ok)
            {
                assert(value.port == 17 && value.name.bytes == prior.value);
                assert(arena.stats().used == used);
            }
            const read = arena.read(prior.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
                assert(bytes.length == 5 && bytes[0] == 's');
            });
            assert(read == Status.ok);
        }
    }
}
else
{
    @("YAML explicitly reports unavailable provider support")
    unittest
    {
        ubyte[16] storage;
        scope arena = RequestArena(storage[]);
        Payload payload;
        const error = decodeYamlInto(cast(const(ubyte)[]) "port: 1", payload, arena);
        assert(error.code == Status.unsupported);
        assert(encodeYaml(payload, arena).error.code == Status.unsupported);
    }
}
