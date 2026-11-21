module data_boundaries;

import flint.arena : Buffer, RequestArena, Status, Text;
import flint.data : mapRow;

@safe:

private struct Cells
{
    Text text;
    Buffer blob;
    double number;
    byte narrow;
}

private void checkLength(scope const(ubyte)[] bytes, ref scope RequestArena arena)
{
    Cells result;
    assert(mapRow(result, arena, "text", bytes).code == Status.ok);
    assert(result.text.bytes.length() == bytes.length);
    assert(mapRow(result, arena, "blob", bytes).code == Status.ok);
    assert(result.blob.length() == bytes.length);
    assert(arena.reset() == Status.ok);
    assert(arena.read(result.blob, (scope const(ubyte)[]) @safe nothrow @nogc {}) != Status.ok);
}

@("deterministic codec length, UTF-8 and scalar bounds")
unittest
{
    auto space = new ubyte[2 * 1_048_577 + 7];
    scope arena = RequestArena(space);
    auto input = new ubyte[1_048_577];
    input[] = cast(ubyte) 'a';
    foreach (length; 0 .. 257)
        checkLength(input[0 .. length], arena);
    foreach (length; [1023, 1024, 1025, 1_048_575, 1_048_576, 1_048_577])
        checkLength(input[0 .. length], arena);

    Cells result;
    foreach (bad; ["\xc0\x80", "\xe2\x82", "\xed\xa0\x80", "\xf4\x90\x80\x80"])
        assert(mapRow(result, arena, "text", cast(const(ubyte)[]) bad).code == Status.invalidArgument);
    assert(mapRow(result, arena, "number", cast(const(ubyte)[]) "0.125").code == Status.ok);
    assert(result.number == 0.125);
    assert(mapRow(result, arena, "number", cast(const(ubyte)[]) "1e999").code == Status.invalidArgument);
    assert(mapRow(result, arena, "narrow", cast(const(ubyte)[]) "-128").code == Status.ok && result.narrow == byte.min);
    assert(mapRow(result, arena, "narrow", cast(const(ubyte)[]) "128").code == Status.invalidArgument);

    ubyte[8] tinyStorage;
    scope tiny = RequestArena(tinyStorage[]);
    assert(mapRow(result, tiny, "text", input[0 .. 9]).code != Status.ok);
}
