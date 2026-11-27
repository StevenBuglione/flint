module stream_null_callback_test;

import flint.java.lang : IllegalStateException, NullPointerException;
import flint.java.util : Comparator;
import flint.java.util.stream : Stream;

@safe:

// Temurin 21.0.13+9 (StageNullOracle, MatchOracle, FlatMapNullMapperOracle, ReduceNullOracle): a null stage or terminal callback
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
    // Both reduce overloads, and min and max through BinaryOperator.minBy/maxBy, reject null before the take.
    int delegate(int, int) @safe accumulator;
    Comparator!int comparator;
    assertEagerNull("reduce identity", (Stream!int source) { source.reduce(0, accumulator); });
    assertEagerNull("reduce", (Stream!int source) { source.reduce(accumulator); });
    assertEagerNull("min", (Stream!int source) { source.min(comparator); });
    assertEagerNull("max", (Stream!int source) { source.max(comparator); });

    assert(Stream!int.of(13, 8, 21).reduce(7, (int a, int b) => a + b) == 49);
    assert(Stream!int.of(13, 8, 21).reduce((int a, int b) => a + b).get() == 42);
}

unittest
{
    // Optional.of on the selected or folded reference: a null result throws instead of reading as empty.
    static final class Box
    {
    }

    auto box = new Box;
    Box nothing;
    auto nullsFirst = Comparator!Box.of((Box a, Box b) => (a !is null) - (b !is null));
    assert(run(() { Stream!Box.of(nothing).reduce((Box a, Box b) => a is null ? a : b); }) == Outcome.nullPointer);
    assert(run(() { Stream!Box.of(box, box).reduce((Box a, Box b) => a is b ? null : a); }) == Outcome.nullPointer);
    assert(run(() { Stream!Box.of(box, nothing).min(nullsFirst); }) == Outcome.nullPointer);
    assert(run(() { Stream!Box.of(nothing, box).max(nullsFirst.reversed()); }) == Outcome.nullPointer);
    assert(run(() { Stream!Box.of(nothing, box).findFirst(); }) == Outcome.nullPointer);
    assert(run(() { Stream!Box.of(nothing).findAny(); }) == Outcome.nullPointer);
    assert(Stream!Box.of(box, nothing).findFirst().get() is box);
    assert(Stream!Box.of(box, nothing).max(nullsFirst).get() is box);
    assert(Stream!Box.empty().findFirst().isEmpty());
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

unittest
{
    // TerminalNullOracle and TerminalSupplierOracle: forEach and forEachOrdered on a source stream take it before
    // rejecting the null action, so it is spent; a derived stage rejects the action first and stays usable.
    void delegate(int) @safe action;
    foreach (ordered; [false, true])
    {
        void apply(Stream!int stream)
        {
            if (ordered)
                stream.forEachOrdered(action);
            else
                stream.forEach(action);
        }

        auto head = Stream!int.empty();
        assert(run(() { apply(head); }) == Outcome.nullPointer);
        assert(run(() { apply(head); }) == Outcome.illegalState);

        int[] seen;
        auto derived = Stream!int.of(7).map!int((int value) => value * 2);
        assert(run(() { apply(derived); }) == Outcome.nullPointer);
        derived.forEachOrdered((int value) { seen ~= value; });
        assert(seen == [14]);
        assert(run(() { apply(derived); }) == Outcome.nullPointer);
    }

    int[] order;
    Stream!int.of(3, 1, 2).peek((int value) { order ~= value; }).forEach((int value) {
        order ~= -value;
    });
    assert(order == [3, -3, 1, -1, 2, -2]);
}
