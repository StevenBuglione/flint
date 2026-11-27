module iterable_foreach_test;

import core.memory : GC;
import flint.java.lang : IllegalStateException, Iterable, NullPointerException, UnsupportedOperationException;
import flint.java.util : ArrayList, HashSet, Iterator, NoSuchElementException;
import flint.java.util.function_.consumer : Consumer;

@safe:

private final class SliceIterator(T) : Iterator!T
{
    private const(T)[] items;
    private size_t index;

    this(const(T)[] items) pure nothrow @nogc
    {
        this.items = items;
    }

    override bool hasNext()
    {
        return index < items.length;
    }

    override T next()
    {
        if (index >= items.length)
            throw new NoSuchElementException();
        return cast(T) items[index++];
    }

    override void remove()
    {
        throw new UnsupportedOperationException();
    }
}

private class RecordingIterable(T) : Iterable!T
{
    private T[] items;
    size_t iteratorCalls;
    size_t opApplyCalls;

    this(T[] items) pure nothrow @nogc
    {
        this.items = items;
    }

    override Iterator!T iterator()
    {
        ++iteratorCalls;
        return new SliceIterator!T(items);
    }

    mixin Iterable!T.Defaults;

    override int opApply(scope int delegate(T) @safe dg)
    {
        ++opApplyCalls;
        foreach (item; items)
            if (const result = dg(item))
                return result;
        return 0;
    }
}

private final class CustomOverrideIterable : RecordingIterable!string
{
    size_t customConsumerCalls;

    this(string[] items) pure nothrow @nogc
    {
        super(items);
    }

    override void forEach(Consumer!string action)
    {
        ++customConsumerCalls;
        if (action is null)
            throw new NullPointerException();
        foreach_reverse (item; items)
            action.accept(item);
    }
}

private final class RecordingConsumer(T) : Consumer!T
{
    T[] seen;

    override void accept(T value)
    {
        seen ~= value;
    }
}

private final class SummingIntConsumer : Consumer!int
{
    int sum;

    override void accept(int value) pure nothrow @nogc
    {
        sum += value;
    }
}

private final class ItemObject
{
    int weight;

    this(int weight) pure nothrow @nogc
    {
        this.weight = weight;
    }
}

private final class SummingItemConsumer : Consumer!ItemObject
{
    int sum;

    override void accept(ItemObject value) pure nothrow @nogc
    {
        sum += value.weight;
    }
}

@("Iterable.forEach: bare null rejected at compile time; typed null throws NPE before iteration")
unittest
{
    auto empty = new RecordingIterable!string(null);
    auto nonEmpty = new RecordingIterable!string(["a", "b", "c"]);
    Iterable!string emptyView = empty;
    Iterable!string nonEmptyView = nonEmpty;

    static assert(!__traits(compiles, emptyView.forEach(null)));
    static assert(!__traits(compiles, empty.forEach(null)));
    static assert(!__traits(compiles, (new ArrayList!int()).forEach(null)));
    static assert(!__traits(compiles, (new HashSet!int()).forEach(null)));

    Consumer!string absentConsumer;
    void delegate(string) @safe absentDelegate;

    foreach (view; [emptyView, nonEmptyView])
    {
        NullPointerException caught;
        try
            view.forEach(absentConsumer);
        catch (NullPointerException ex)
            caught = ex;
        assert(caught !is null && caught.getMessage() is null);

        caught = null;
        try
            view.forEach(absentDelegate);
        catch (NullPointerException ex)
            caught = ex;
        assert(caught !is null && caught.getMessage() is null);
    }
    assert(empty.iteratorCalls == 0 && empty.opApplyCalls == 0);
    assert(nonEmpty.iteratorCalls == 0 && nonEmpty.opApplyCalls == 0);

    auto emptyList = new ArrayList!int();
    Consumer!int absentIntConsumer;
    NullPointerException listError;
    try
        emptyList.forEach(absentIntConsumer);
    catch (NullPointerException ex)
        listError = ex;
    assert(listError !is null && listError.getMessage() is null);
}

@("Iterable.forEach(Consumer): order, andThen composition, early exception stop, and virtual override")
unittest
{
    auto items = new RecordingIterable!string(["a", "b", "c"]);
    Iterable!string view = items;

    string[] log;
    auto first = Consumer!string.of((string s) { log ~= "1:" ~ s; });
    auto second = Consumer!string.of((string s) { log ~= "2:" ~ s; });
    view.forEach(first.andThen(second));
    assert(log == ["1:a", "2:a", "1:b", "2:b", "1:c", "2:c"]);
    assert(items.opApplyCalls == 1 && items.iteratorCalls == 0);

    string[] partial;
    auto stop = Consumer!string.of((string s) {
        partial ~= s;
        if (s == "b")
            throw new IllegalStateException("stop");
    });
    IllegalStateException failure;
    try
        view.forEach(stop);
    catch (IllegalStateException ex)
        failure = ex;
    assert(failure !is null && failure.getMessage() == "stop");
    assert(partial == ["a", "b"]);

    auto overridden = new CustomOverrideIterable(["x", "y"]);
    Iterable!string overriddenView = overridden;
    auto recorder = new RecordingConsumer!string();
    overriddenView.forEach(recorder);
    assert(overridden.customConsumerCalls == 1);
    assert(recorder.seen == ["y", "x"]);
}

@("Iterable.forEach(Consumer): collections dispatch and zero GC allocations on hot traversal")
unittest
{
    auto ints = new ArrayList!int();
    ints.add(10);
    ints.add(20);
    ints.add(30);
    auto intSum = new SummingIntConsumer();
    Iterable!int intView = ints;

    // Non-erased ArrayList!int dispatches through Iterable!int.Defaults.
    intView.forEach(intSum);
    assert(intSum.sum == 60);

    // Zero-allocation traversal over erased ArrayList and erased HashSet (proving Defaults allocates no closure).
    auto erasedList = new ArrayList!ItemObject();
    auto erasedSet = new HashSet!ItemObject();
    auto a = new ItemObject(3);
    auto b = new ItemObject(7);
    erasedList.add(a);
    erasedList.add(b);
    erasedSet.add(a);
    erasedSet.add(b);
    auto itemSum = new SummingItemConsumer();
    Iterable!ItemObject erasedListView = erasedList;
    Iterable!ItemObject erasedSetView = erasedSet;

    erasedListView.forEach(itemSum);
    assert(itemSum.sum == 10);
    itemSum.sum = 0;
    const beforeErasedList = GC.stats().allocatedInCurrentThread;
    erasedListView.forEach(itemSum);
    const afterErasedList = GC.stats().allocatedInCurrentThread;
    assert(itemSum.sum == 10 && afterErasedList == beforeErasedList);

    itemSum.sum = 0;
    const beforeErasedSet = GC.stats().allocatedInCurrentThread;
    erasedSetView.forEach(itemSum);
    const afterErasedSet = GC.stats().allocatedInCurrentThread;
    assert(itemSum.sum == 10 && afterErasedSet == beforeErasedSet);

    // Zero-allocation traversal over a custom opApply Iterable using Defaults.
    auto custom = new RecordingIterable!int([4, 5, 6]);
    Iterable!int customView = custom;
    intSum.sum = 0;
    const beforeCustom = GC.stats().allocatedInCurrentThread;
    customView.forEach(intSum);
    const afterCustom = GC.stats().allocatedInCurrentThread;
    assert(intSum.sum == 15 && afterCustom == beforeCustom);
}
