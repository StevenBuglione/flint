/// The native event callback may not retain libyaml-owned bytes.
module yaml_event_escape;

import flint.arena : Error;
import flint.serde.ffi.yaml_events : EventKind, Tag, visitEvents;

@safe:

private const(ubyte)[] escaped;

/// Intentionally fail the scope check when the optional provider is enabled.
Error rejectEscape(scope const(ubyte)[] input) nothrow @nogc
{
    return visitEvents(input, (EventKind, Tag, size_t, scope const(ubyte)[] bytes) @safe nothrow @nogc {
        escaped = bytes;
        return Error.init;
    });
}
