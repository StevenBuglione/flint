/// Verify that an arena cannot be returned past the lifetime of borrowed parameter storage.
module escape_parameter;

import flint.arena : RequestArena;

@safe:

/// The compiler must diagnose returning an arena backed by a scope parameter.
RequestArena retainBacking(scope ubyte[] backing) nothrow @nogc
{
    return RequestArena(backing);
}
