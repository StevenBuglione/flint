/// The native normalization callback may not retain its temporary buffer.
module yaml_scratch_escape;

import flint.arena : Error;
import flint.serde.ffi.yaml_events : withScratch;

@safe:

private ubyte[] escaped;

/// Intentionally fail the scope check when the optional provider is enabled.
Error rejectEscape() nothrow @nogc
{
    return withScratch(16, (scope ubyte[] bytes) @safe nothrow @nogc {
        escaped = bytes;
        return Error.init;
    });
}
