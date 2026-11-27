module stream_collector_interface_test;

import flint.java.lang : IllegalStateException, NullPointerException, UnsupportedOperationException, valueOf;
import flint.java.util : ArrayList, List, Set;
import flint.java.util.function_ : BiConsumer, BinaryOperator, Function, Supplier;
import flint.java.util.stream : Collector, Stream;
import flint.java.util.stream.collector : Characteristics;

@safe:

// Expected orders come from CollectorInterfaceOracle on Temurin 21.0.13+9.

private final class Log
{
    string[] events;
}

private final class Recording : Collector!(int, List!int, string)
{
    private Log log;
    private bool identity;
    private int nullGetter = -1;

    this(Log log, bool identity = false, int nullGetter = -1)
    {
        this.log = log;
        this.identity = identity;
        this.nullGetter = nullGetter;
    }

    Supplier!(List!int) supplier()
    {
        log.events ~= "supplier()";
        if (nullGetter == 0)
            return null;
        auto events = log;
        return Supplier!(List!int).of(() {
            events.events ~= "get";
            return cast(List!int) new ArrayList!int();
        });
    }

    BiConsumer!(List!int, int) accumulator()
    {
        log.events ~= "accumulator()";
        if (nullGetter == 1)
            return null;
        auto events = log;
        return BiConsumer!(List!int, int).of((List!int list, int e) {
            events.events ~= "accept " ~ valueOf(e);
            list.add(e);
        });
    }

    BinaryOperator!(List!int) combiner()
    {
        log.events ~= "combiner()";
        if (nullGetter == 2)
            return null;
        return new First!(List!int);
    }

    Function!(List!int, string) finisher()
    {
        log.events ~= "finisher()";
        if (nullGetter == 3)
            return null;
        auto events = log;
        return Function!(List!int, string).of((List!int list) {
            events.events ~= "apply";
            return valueOf(list.size());
        });
    }

    Set!Characteristics characteristics()
    {
        log.events ~= "characteristics()";
        if (nullGetter == 4)
            return null;
        return identity ? Set!Characteristics.of(Characteristics.IDENTITY_FINISH) : Set!Characteristics.of();
    }
}

private final class First(T) : BinaryOperator!T
{
    T apply(T left, T)
    {
        return left;
    }
}

private Stream!int recorded(Log log, int[] items...)
{
    return Stream!int.ofArray(items.dup).peek((int e) { log.events ~= "read " ~ valueOf(e); });
}

unittest
{
    auto log = new Log;
    assert(recorded(log, 1, 2).collect(new Recording(log)) == "2");
    assert(log.events == [
        "supplier()", "accumulator()", "combiner()", "characteristics()", "get", "read 1",
        "accept 1", "read 2", "accept 2", "characteristics()", "finisher()", "apply"
    ]);
}

unittest
{
    // Under IDENTITY_FINISH the container is returned without fetching the finisher.
    auto log = new Log;
    auto identity = new Recording(log, true);
    auto container = Stream!int.of(1, 2).collect(cast(Collector!(int, List!int, List!int)) identityView(identity));
    assert(container.size() == 2);
    assert(log.events == [
        "supplier()", "accumulator()", "combiner()", "characteristics()", "get", "accept 1",
        "accept 2", "characteristics()"
    ]);
}

// Java collects through a raw cast here; D keeps the types and forwards the same getters.
private Collector!(int, List!int, List!int) identityView(Recording recording)
{
    return new class Collector!(int, List!int, List!int)
    {
        Supplier!(List!int) supplier()
        {
            return recording.supplier();
        }

        BiConsumer!(List!int, int) accumulator()
        {
            return recording.accumulator();
        }

        BinaryOperator!(List!int) combiner()
        {
            return recording.combiner();
        }

        Function!(List!int, List!int) finisher()
        {
            recording.finisher();
            return null;
        }

        Set!Characteristics characteristics()
        {
            return recording.characteristics();
        }
    };
}

unittest
{
    auto log = new Log;
    auto stream = Stream!int.of(1, 2);
    stream.count();
    try
    {
        stream.collect(new Recording(log));
        assert(false);
    }
    catch (IllegalStateException e)
    {
        assert(e.msg == "stream has already been operated upon or closed");
    }
    assert(log.events == ["supplier()", "accumulator()", "combiner()"]);

    Collector!(int, List!int, string) none;
    try
    {
        Stream!int.of(1).collect(none);
        assert(false);
    }
    catch (NullPointerException e)
    {
        assert(e.msg.length == 0);
    }
}

unittest
{
    // A null function from a getter throws NullPointerException only where Java dereferences it.
    static immutable before = ["supplier()", "accumulator()", "combiner()", "characteristics()"];
    static immutable after = before ~ ["characteristics()", "finisher()"];
    static struct Case
    {
        int getter;
        int size;
        bool threw;
        immutable(string)[] getters;
    }

    static immutable Case[] cases = [
        Case(0, 0, true, before), Case(0, 1, true, before), Case(1, 0, false, after),
        Case(1, 1, true, before), Case(2, 0, false, after), Case(2, 1, false, after),
        Case(3, 0, true, after), Case(3, 1, true, after), Case(4, 0, true, before),
        Case(4, 1, true, before),
    ];
    foreach (c; cases)
    {
        auto log = new Log;
        bool threw;
        try
            Stream!int.ofArray(c.size ? [1] : null).collect(new Recording(log, false, c.getter));
        catch (NullPointerException e)
            threw = true;
        string[] getters;
        foreach (e; log.events)
            if (e[$ - 1] == ')')
                getters ~= e;
        assert(threw == c.threw && getters == c.getters, valueOf(c.getter) ~ "/" ~ valueOf(c.size));
    }
}

unittest
{
    auto joined = Collector!(int, string[], string).of(() => cast(string[]) null, (string[] parts, int e) {
        parts ~= valueOf(e);
    }, (string[] l, string[] r) => l ~ r, (string[] parts) => valueOf(parts.length));
    assert(joined.characteristics().isEmpty());
    auto builder = Collector!(int, ArrayList!int, int).of(() => new ArrayList!int(), (ArrayList!int list, int e) {
        list.add(e);
    }, (ArrayList!int l, ArrayList!int _) => l, (ArrayList!int list) => list.size());
    assert(Stream!int.of(1, 2, 3).collect(builder) == 3);

    auto unordered = Collector!(int, ArrayList!int, ArrayList!int).of(() => new ArrayList!int(),
            (ArrayList!int list, int e) { list.add(e); }, (ArrayList!int l, ArrayList!int _) => l,
            Characteristics.UNORDERED, Characteristics.UNORDERED);
    assert(unordered.characteristics().toArray() == [
        Characteristics.UNORDERED, Characteristics.IDENTITY_FINISH
    ]);
    auto container = new ArrayList!int();
    assert(unordered.finisher().apply(container) is container);
    assert(Stream!int.of(1, 2).collect(unordered).size() == 2);
    try
    {
        unordered.characteristics().add(Characteristics.CONCURRENT);
        assert(false);
    }
    catch (UnsupportedOperationException e)
    {
    }

    auto concurrent = Collector!(int, ArrayList!int, int).of(() => new ArrayList!int(), (ArrayList!int list, int e) {
        list.add(e);
    }, (ArrayList!int l, ArrayList!int _) => l, (ArrayList!int list) => list.size(),
            Characteristics.IDENTITY_FINISH, Characteristics.CONCURRENT);
    assert(concurrent.characteristics().toArray() == [
        Characteristics.CONCURRENT, Characteristics.IDENTITY_FINISH
    ]);
    assert(Collector!(int, int, int).Characteristics.UNORDERED == Characteristics.UNORDERED);
}

unittest
{
    // Collector.of rejects each null function; a null characteristics array counts as empty (R26), and a null
    // characteristic does not compile because the enum is a value type (R20).
    alias C = Collector!(int, ArrayList!int, int);
    auto supplier = Supplier!(ArrayList!int).of(() => new ArrayList!int());
    auto accumulator = BiConsumer!(ArrayList!int, int).of((ArrayList!int, int) {});
    BinaryOperator!(ArrayList!int) combiner = new First!(ArrayList!int);
    auto finisher = Function!(ArrayList!int, int).of((ArrayList!int _) => 0);
    foreach (i; 0 .. 4)
    {
        try
        {
            C.of(i == 0 ? null : supplier, i == 1 ? null : accumulator, i == 2 ? null : combiner, i == 3 ? null
                    : finisher);
            assert(false);
        }
        catch (NullPointerException e)
        {
            assert(e.msg.length == 0);
        }
    }
    assert(C.of(supplier, accumulator, combiner, finisher, null).characteristics().isEmpty());
    static assert(!__traits(compiles, C.of(supplier, accumulator, combiner, finisher, null, null)));
}
