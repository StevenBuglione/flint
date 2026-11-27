module stream_null_callback_test;

import flint.java.lang : IllegalStateException, NullPointerException;
import flint.java.util.stream : Stream;

@safe:

// Temurin 21.0.13+9 (StageNullOracle, MatchOracle, FlatMapNullMapperOracle): a null stage or terminal callback
// throws NullPointerException before the source is taken, so a fresh source stays usable and a spent source
// reports the null callback rather than its reuse.

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

private void assertEagerNull(string name, scope void delegate(Stream!int) @safe stage)
{
    auto source = Stream!int.of(7);
    assert(run(() { stage(source); }) == Outcome.nullPointer, name ~ ": fresh source accepted a null callback");
    assert(source.findFirst().get() == 7, name ~ ": the null callback consumed the fresh source");
    assert(run(() { stage(source); }) == Outcome.nullPointer, name ~ ": spent source checked before the callback");
}

unittest
{
    bool delegate(int) @safe predicate;
    int delegate(int) @safe mapper;
    long delegate(int) @safe longMapper;
    void delegate(int) @safe action;
    Stream!int delegate(int) @safe flatMapper;
    assertEagerNull("filter", (Stream!int source) { source.filter(predicate); });
    assertEagerNull("map", (Stream!int source) { source.map!int(mapper); });
    assertEagerNull("mapToInt", (Stream!int source) { source.mapToInt(mapper); });
    assertEagerNull("mapToLong", (Stream!int source) { source.mapToLong(longMapper); });
    assertEagerNull("peek", (Stream!int source) { source.peek(action); });
    assertEagerNull("flatMap", (Stream!int source) { source.flatMap!int(flatMapper); });
    assertEagerNull("anyMatch", (Stream!int source) { source.anyMatch(predicate); });
    assertEagerNull("allMatch", (Stream!int source) { source.allMatch(predicate); });
    assertEagerNull("noneMatch", (Stream!int source) { source.noneMatch(predicate); });
}

unittest
{
    bool delegate(int) @safe predicate;
    assert(run(() { Stream!int.empty().anyMatch(predicate); }) == Outcome.nullPointer);
    assert(run(() { Stream!int.empty().allMatch(predicate); }) == Outcome.nullPointer);
    assert(run(() { Stream!int.empty().noneMatch(predicate); }) == Outcome.nullPointer);
}

unittest
{
    // Java validates the operator when iterate is called, before the seed could be pulled.
    int delegate(int) @safe operator;
    assert(run(() { Stream!int.iterate(7, operator); }) == Outcome.nullPointer);
}

unittest
{
    // Non-null callbacks keep their laziness and short-circuiting.
    int calls;
    auto stage = Stream!int.iterate(7, (int value) => value + 1).map!int((int value) {
        calls++;
        return value * 2;
    });
    assert(calls == 0);
    assert(stage.findFirst().get() == 14);
    assert(calls == 1);

    int tested;
    assert(Stream!int.of(1, 2, 3).anyMatch((int value) { tested++; return value == 2; }));
    assert(tested == 2);
    tested = 0;
    assert(!Stream!int.of(1, 2, 3).allMatch((int value) { tested++; return value == 1; }));
    assert(tested == 2);
    tested = 0;
    assert(!Stream!int.of(1, 2, 3).noneMatch((int value) { tested++; return value == 2; }));
    assert(tested == 2);

    auto spent = Stream!int.of(1);
    spent.filter((int) => true);
    assert(run(() { spent.filter((int) => true); }) == Outcome.illegalState);
}
