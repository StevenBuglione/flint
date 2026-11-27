module stream_concat_null_test;

import flint.java.lang : IllegalStateException, NullPointerException;
import flint.java.util.stream : Stream;

@safe:

// Temurin 21.0.13+9 (ConcatOracle): concat rejects either null input before taking either stream, so the other
// input stays usable and a spent left with a null right reports the null rather than the reuse.

private enum Outcome
{
    accepted,
    nullPointer,
    illegalState,
}

private Outcome run(scope void delegate() @safe operation)
{
    try
    {
        operation();
        return Outcome.accepted;
    }
    catch (NullPointerException)
        return Outcome.nullPointer;
    catch (IllegalStateException)
        return Outcome.illegalState;
}

unittest
{
    auto first = Stream!int.of(1);
    assert(run(() { Stream!int.concat(first, null); }) == Outcome.nullPointer);
    assert(first.findFirst().get() == 1);
    assert(run(() { Stream!int.concat(first, null); }) == Outcome.nullPointer);
}

unittest
{
    auto second = Stream!int.of(2);
    assert(run(() { Stream!int.concat(null, second); }) == Outcome.nullPointer);
    assert(second.findFirst().get() == 2);
}

unittest
{
    auto unused = Stream!int.of(3), spent = Stream!int.of(2);
    spent.findFirst();
    assert(run(() { Stream!int.concat(unused, spent); }) == Outcome.illegalState);
    assert(run(() { unused.findFirst(); }) == Outcome.illegalState);
}

unittest
{
    int[] seen;
    auto left = Stream!int.of(1, 2).map!int((int value) { seen ~= value; return value; });
    auto right = Stream!int.of(3, 4).map!int((int value) { seen ~= value; return value; });
    auto joined = Stream!int.concat(left, right);
    assert(seen.length == 0);
    assert(joined.findFirst().get() == 1);
    assert(seen == [1]);
}
