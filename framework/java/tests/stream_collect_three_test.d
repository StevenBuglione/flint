module stream_collect_three_test;

import flint.java.lang : IllegalArgumentException, IllegalStateException, NullPointerException;
import flint.java.util : ArrayList, List;
import flint.java.util.function_ : BiConsumer, Supplier;
import flint.java.util.stream : Stream;

@safe:

// Temurin 21.0.13 (CollectThreeOracle): the three-argument collect supplies its container before the first element is
// read, accumulates each element as it is read, never combines, and returns the container, null included.

unittest
{
    string[] events;
    auto result = Stream!int.of(1, 2, 3).peek((int e) { events ~= "read"; }).collect!(ArrayList!int)(() {
        events ~= "get";
        return new ArrayList!int();
    }, (ArrayList!int list, int e) { events ~= "accept"; list.add(e); }, (ArrayList!int, ArrayList!int) {
        events ~= "combine";
    });
    assert(result.toString() == "[1, 2, 3]", result.toString());
    assert(events == ["get", "read", "accept", "read", "accept", "read", "accept"]);

    events = null;
    auto empty = Stream!int.empty().collect!(ArrayList!int)(() {
        events ~= "get";
        return new ArrayList!int();
    }, (ArrayList!int, int) { events ~= "accept"; }, (ArrayList!int, ArrayList!int) {
        events ~= "combine";
    });
    assert(empty.isEmpty() && events == ["get"]);
}

unittest
{
    // A null container goes to the accumulator and is the result.
    assert(Stream!int.empty().collect!(ArrayList!int)(() => null, (ArrayList!int, int) {},
            (ArrayList!int, ArrayList!int) {}) is null);
    int accepted;
    Stream!int.of(1).collect!(ArrayList!int)(() => null, (ArrayList!int l, int) {
        assert(l is null);
        accepted++;
    }, (ArrayList!int, ArrayList!int) {});
    assert(accepted == 1);
}

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

private alias L = ArrayList!int;

// A null function throws before the source is taken: a fresh source stays usable, a spent one reports the null.
private void checkNullDelegate(int which)
{
    L delegate() @safe supplier = which == 0 ? null : () => new L();
    void delegate(L, int) @safe accumulator = which == 1 ? null : (L l, int e) { l.add(e); };
    void delegate(L, L) @safe combiner = which == 2 ? null : (L a, L b) { a.addAll(b); };
    auto source = Stream!int.of(7);
    assert(run(() { source.collect!L(supplier, accumulator, combiner); }) == Outcome.nullPointer);
    assert(source.findFirst().get() == 7);
    assert(run(() { source.collect!L(supplier, accumulator, combiner); }) == Outcome.nullPointer);
}

private void checkNullInterface(int which)
{
    Supplier!L supplier = which == 0 ? null : Supplier!L.of(() => new L());
    BiConsumer!(L, int) accumulator = which == 1 ? null : BiConsumer!(L, int).of((L l, int e) {
        l.add(e);
    });
    BiConsumer!(L, L) combiner = which == 2 ? null : BiConsumer!(L, L).of((L a, L b) { a.addAll(b); });
    auto source = Stream!int.of(7);
    assert(run(() { source.collect!L(supplier, accumulator, combiner); }) == Outcome.nullPointer);
    assert(source.findFirst().get() == 7);
}

unittest
{
    foreach (which; 0 .. 3)
    {
        checkNullDelegate(which);
        checkNullInterface(which);
    }

    auto spent = Stream!int.of(1);
    spent.count();
    assert(run(() {
            spent.collect!(ArrayList!int)(() => new ArrayList!int(), (ArrayList!int l, int e) {
                l.add(e);
            }, (ArrayList!int, ArrayList!int) {});
        }) == Outcome.illegalState);
}

unittest
{
    // Java's functional interfaces.
    auto list = Stream!int.of(4, 5).collect(Supplier!(ArrayList!int)
            .of(() => new ArrayList!int()), BiConsumer!(ArrayList!int, int).of((ArrayList!int l, int e) {
            l.add(e);
        }), BiConsumer!(ArrayList!int, ArrayList!int).of((ArrayList!int a, ArrayList!int b) {
            a.addAll(b);
        }));
    assert(list.toString() == "[4, 5]", list.toString());

    // With R given, untyped block lambdas infer their parameter types.
    auto inferred = Stream!int.of(6, 7).collect!(ArrayList!int)(() => new ArrayList!int(), (l, e) {
        l.add(e);
    }, (a, b) { a.addAll(b); });
    assert(inferred.toString() == "[6, 7]", inferred.toString());
}

unittest
{
    // A throwing accumulator stops traversal; limit reads only the elements it passes on.
    int reads;
    try
    {
        Stream!int.of(1, 2, 3).peek((int e) { reads++; }).collect!(ArrayList!int)(() => new ArrayList!int(),
                (ArrayList!int l, int e) {
            if (e == 2)
                throw new IllegalArgumentException("two");
            l.add(e);
        }, (ArrayList!int, ArrayList!int) {});
        assert(false);
    }
    catch (IllegalArgumentException e)
        assert(e.getMessage() == "two" && reads == 2);

    reads = 0;
    auto limited = Stream!int.iterate(1, (int x) => x + 1).peek((int e) { reads++; }).limit(2)
        .collect!(ArrayList!int)(() => new ArrayList!int(), (ArrayList!int l, int e) { l.add(e); },
            (ArrayList!int a, ArrayList!int b) { a.addAll(b); });
    assert(limited.toString() == "[1, 2]" && reads == 2);
}
