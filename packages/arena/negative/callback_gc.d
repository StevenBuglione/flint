/// Verify that an arena callback cannot call a GC-allocating function.
module callback_gc;

import flint.arena : Buffer, RequestArena, Status;

@safe:

private ubyte[] gcAllocation()
{
    return new ubyte[1];
}

/// The compiler must diagnose the call to gcAllocation inside the callback.
Status rejectAllocation(ref scope RequestArena arena, Buffer handle) nothrow @nogc
{
    return arena.read(handle, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        auto allocated = gcAllocation();
        if (bytes.length == 1)
            allocated[0] = bytes[0];
    });
}
