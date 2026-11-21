module sink_escape;

import flint.arena : Status;
import flint.log : LogOptions;

@safe:

/// Compiler-negative witness for a sink that attempts to retain the consumer's reusable line.
LogOptions retainBorrow()
{
    const(char)[] held;
    LogOptions options;
    options.sink = (scope const(char)[] line) @safe nothrow @nogc { held = line; return Status.ok; };
    return options;
}
