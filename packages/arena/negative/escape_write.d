/// Verify that a writable callback slice cannot be retained after the borrow ends.
module escape_write;

import flint.arena : Buffer, RequestArena, Status;

@safe:

private ubyte[] retained;

/// The compiler must diagnose storing the scoped writable slice in a global.
Status retainWritable(ref scope RequestArena arena, Buffer handle) nothrow @nogc
{
    return arena.write(handle, (scope ubyte[] bytes) @safe nothrow @nogc { retained = bytes; });
}
