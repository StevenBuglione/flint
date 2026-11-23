/// Compile-negative fixture for duplicate serialization names.
module duplicate_name;

import flint.arena : Error, RequestArena;
import flint.serde : JsonName, decodeInto;

@safe:

private struct Invalid
{
    @JsonName("same")
    int first;
    @JsonName("same")
    int second;
}

/// Instantiating the hot decoder must reject this DTO shape.
Error rejected(ref scope RequestArena arena) nothrow @nogc
{
    Invalid destination;
    return decodeInto(cast(const(ubyte)[]) "{}", destination, arena);
}
