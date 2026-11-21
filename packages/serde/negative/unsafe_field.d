/// Compile-negative fixture for unsafe pointers in the hot DTO.
module unsafe_field;

import flint.arena : Error, RequestArena;
import flint.serde : decodeInto;

@safe:

private struct Invalid
{
    int* pointer;
}

/// Instantiating the hot decoder must reject this DTO shape.
Error rejected(ref scope RequestArena arena) nothrow @nogc
{
    Invalid destination;
    return decodeInto(cast(const(ubyte)[]) "{}", destination, arena);
}
