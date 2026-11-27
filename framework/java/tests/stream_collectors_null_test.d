module stream_collectors_null_test;

import flint.java.lang : IllegalStateException, NullPointerException;
import flint.java.util.stream : Collectors, Stream;

@safe:

unittest
{
    int[] visited;
    auto withNull = Stream!string.of("a", null, "c").peek((string e) {
        visited ~= cast(int) visited.length;
    });
    try
    {
        withNull.collect(Collectors.toUnmodifiableList());
        assert(false);
    }
    catch (NullPointerException e)
    {
        assert(e.msg.length == 0);
    }
    assert(visited.length == 3);
    assert(Stream!string.of("a", "b").collect(Collectors.toUnmodifiableList()).size() == 2);
}

unittest
{
    string[] keys;
    auto toMap = Collectors.toMap((string e) { keys ~= e; return e; }, (string e) => e == "b" ? null : e);
    try
    {
        Stream!string.of("a", "b", "c").collect(toMap);
        assert(false);
    }
    catch (NullPointerException e)
    {
        assert(e.msg.length == 0);
    }
    assert(keys == ["a", "b"]);
    auto map = Stream!int.of(1, 2).collect(Collectors.toMap((int e) => e, (int e) => e * 10));
    assert(map.get(2) == 20);
}

unittest
{
    try
    {
        Stream!string.of("x", null, "x").collect(Collectors.toMap((string e) => e, (string _) => "v"));
        assert(false);
    }
    catch (IllegalStateException e)
    {
        assert(e.msg == "Duplicate key x (attempted merging values v and v)");
    }
}

unittest
{
    string[] classified;
    auto grouping = Collectors.groupingBy((string e) { classified ~= e; return e == "b" ? null : e; });
    try
    {
        Stream!string.of("a", "b", "c").collect(grouping);
        assert(false);
    }
    catch (NullPointerException e)
    {
        assert(e.msg == "element cannot be mapped to a null key");
    }
    assert(classified == ["a", "b"]);
    auto groups = Stream!int.of(1, 2, 3).collect(Collectors.groupingBy((int e) => e % 2));
    assert(groups.get(1).size() == 2);
}
