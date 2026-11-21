module sink_escape;

import flint.conc : Context;
import flint.os : stream;

@safe:

/// Compiler-negative witness for the scope-limited stream callback.
void retainBorrow()
{
    Context context;
    const(ubyte)[] retained;
    stream(context, ["/bin/sh", "-c", "printf x"], (scope const(ubyte)[] borrowed) @safe {
        retained = borrowed;
    }, null);
}
