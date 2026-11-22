/// Compile-negative fixture for flattened and directly declared names that collide.
module flatten_collision;

import flint.arena : Error, RequestArena;
import flint.serde : JsonFlatten, decodeInto;

@safe:

private struct Invalid
{
    static struct Nested
    {
        int name;
    }

    Nested nested;
    @JsonFlatten Nested flattened;
    int name;
}

/// Instantiating the hot decoder must reject this DTO shape.
Error rejected(ref scope RequestArena arena) nothrow @nogc
{
    Invalid destination;
    return decodeInto(cast(const(ubyte)[]) "{}", destination, arena);
}
