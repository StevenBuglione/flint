module stream_collector_order_test;

import flint.java.lang : IllegalArgumentException, NullPointerException, valueOf;
import flint.java.util.stream : Collectors, Stream;

@safe:

// Java's Stream.collect supplies the container before pulling, accumulates each element as it is read, then
// finishes (CollectorOrderOracle on Temurin 21.0.13+9).
private final class Log
{
    string[] events;
}

private struct RecordingCollector
{
    Log log;
    IllegalArgumentException failure;

    int[] supply(E)()
    {
        log.events ~= "supply";
        return null;
    }

    void accumulate(ref int[] values, int item)
    {
        log.events ~= "accumulate " ~ valueOf(item);
        if (item == 2 && failure !is null)
            throw failure;
        values ~= item;
    }

    int[] finish(ref int[] values)
    {
        log.events ~= "finish";
        return values;
    }
}

private Stream!int recorded(Log log)
{
    return Stream!int.of(1, 2, 3).peek((int item) { log.events ~= "read " ~ valueOf(item); });
}

unittest
{
    auto log = new Log;
    const result = recorded(log).collect(RecordingCollector(log));
    assert(result == [1, 2, 3]);
    assert(log.events == [
        "supply", "read 1", "accumulate 1", "read 2", "accumulate 2", "read 3", "accumulate 3",
        "finish"
    ]);
}

unittest
{
    auto log = new Log;
    auto failure = new IllegalArgumentException("accumulate 2");
    try
    {
        recorded(log).collect(RecordingCollector(log, failure));
        assert(false);
    }
    catch (IllegalArgumentException actual)
    {
        assert(actual is failure);
    }
    assert(log.events == ["supply", "read 1", "accumulate 1", "read 2", "accumulate 2"]);
}

unittest
{
    auto log = new Log;
    auto toMap = Collectors.toMap((int e) { log.events ~= "key " ~ valueOf(e); return e; },
            (int e) => e == 2 ? null : valueOf(e));
    try
    {
        recorded(log).collect(toMap);
        assert(false);
    }
    catch (NullPointerException e)
    {
        assert(e.msg.length == 0);
    }
    assert(log.events == ["read 1", "key 1", "read 2", "key 2"]);
}

unittest
{
    auto log = new Log;
    auto grouping = Collectors.groupingBy((int e) {
        log.events ~= "classify " ~ valueOf(e);
        return e == 2 ? null : valueOf(e);
    });
    try
    {
        recorded(log).collect(grouping);
        assert(false);
    }
    catch (NullPointerException e)
    {
        assert(e.msg == "element cannot be mapped to a null key");
    }
    assert(log.events == ["read 1", "classify 1", "read 2", "classify 2"]);
}

unittest
{
    // The array form runs the same supply/accumulate/finish steps.
    assert(Collectors.joining(", ", "[", "]").apply(["a", "b"]) == "[a, b]");
    assert(Collectors.joining(", ", "[", "]").apply(cast(string[]) null) == "[]");
    assert(Collectors.counting().apply([1, 2, 3]) == 3);
    assert(Collectors.toList().apply([1, 2]).size() == 2);
    assert(Collectors.toSet().apply([1, 1, 2]).size() == 2);
    assert(Stream!int.of(3, 1).collect(Collectors.joining("-")) == "3-1");
    assert(Stream!int.empty().collect(Collectors.counting()) == 0);
    auto log = new Log;
    assert(recorded(log).collect(Collectors.toUnmodifiableList()).size() == 3);
    assert(log.events == ["read 1", "read 2", "read 3"]);
}
