/// Compile-negative fixture for a JSON default outside the field range.
module invalid_default;

import flint.arena : Error, RequestArena;
import flint.serde : JsonDefault, decodeInto;

@safe:

private struct Invalid
{
    @JsonDefault("256") ubyte value;
}

/// Instantiating the hot decoder must reject this DTO shape.
Error rejected(ref scope RequestArena arena) nothrow @nogc
{
    Invalid destination;
    return decodeInto(cast(const(ubyte)[]) "{}", destination, arena);
}
