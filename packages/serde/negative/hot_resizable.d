/// Compile-negative fixture for dynamic arrays in the hot decoder.
module hot_resizable;

import flint.arena : Error, RequestArena;
import flint.serde : decodeInto;

@safe:

private struct Invalid
{
    int[] numbers;
}

/// Instantiating the hot decoder must reject this DTO shape.
Error rejected(ref scope RequestArena arena) nothrow @nogc
{
    Invalid destination;
    return decodeInto(cast(const(ubyte)[]) "{}", destination, arena);
}
