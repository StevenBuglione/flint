/// Compile-negative fixture for contradictory JSON attributes.
module contradictory_uda;

import flint.arena : Error, RequestArena;
import flint.serde : JsonDefault, JsonRequired, decodeInto;

@safe:

private struct Invalid
{
    @JsonRequired
    @JsonDefault("42")
    int value;
}

/// Instantiating the hot decoder must reject this DTO shape.
Error rejected(ref scope RequestArena arena) nothrow @nogc
{
    Invalid destination;
    return decodeInto(cast(const(ubyte)[]) "{}", destination, arena);
}
