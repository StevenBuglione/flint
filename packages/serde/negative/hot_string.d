/// Compile-negative fixture for unowned strings in the hot decoder.
module hot_string;

import flint.arena : Error, RequestArena;
import flint.serde : decodeInto;

@safe:

private struct Invalid
{
    string text;
}

/// Instantiating the hot decoder must reject this DTO shape.
Error rejected(ref scope RequestArena arena) nothrow @nogc
{
    Invalid destination;
    return decodeInto(cast(const(ubyte)[]) "{}", destination, arena);
}
