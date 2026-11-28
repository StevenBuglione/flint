module copyonwrite_test;

import flint.java.lang : IndexOutOfBoundsException, UnsupportedOperationException;
import flint.java.util : Collection, Iterator, List;
import flint.java.util.concurrent.copyonwritearraylist : CopyOnWriteArrayList;

@safe:

@("empty construction and size")
unittest
{
    auto list = new CopyOnWriteArrayList!int;
    assert(list.size == 0);
    assert(list.isEmpty);
    assert(list.toString == "[]");
}

@("construction from an array copies it")
unittest
{
    int[] source = [1, 2, 3];
    auto list = new CopyOnWriteArrayList!int(source);
    source[0] = 99;
    assert(list.get(0) == 1);
    assert(list.size == 3);
    assert(list.toString == "[1, 2, 3]");
}

@("get, set and index bounds")
unittest
{
    auto list = new CopyOnWriteArrayList!int([1, 2, 3]);
    assert(list.get(1) == 2);
    assert(list.set(1, 20) == 2);
    assert(list.get(1) == 20);
    assert(list.toString == "[1, 20, 3]");
    bool threw;
    try
        list.get(3);
    catch (IndexOutOfBoundsException)
        threw = true;
    assert(threw);
}

@("add appends and inserts")
unittest
{
    auto list = new CopyOnWriteArrayList!int;
    list.add(1);
    list.add(2);
    list.add(0, 0);
    assert(list.toString == "[0, 1, 2]");
    assert(list.size == 3);
}

@("removeAt and remove return the removed element")
unittest
{
    auto list = new CopyOnWriteArrayList!int([1, 2, 3, 2]);
    assert(list.removeAt(1) == 2);
    assert(list.toString == "[1, 3, 2]");
    assert(list.remove(2));
    assert(list.toString == "[1, 3]");
    assert(!list.remove(42));
}

@("iterator is a snapshot")
unittest
{
    auto list = new CopyOnWriteArrayList!int([1, 2, 3]);
    Iterator!int iterator = list.iterator;
    list.add(4);
    assert(iterator.hasNext);
    assert(iterator.next == 1);
    assert(iterator.next == 2);
    assert(iterator.next == 3);
    assert(!iterator.hasNext);
    bool threw;
    try
        iterator.remove;
    catch (UnsupportedOperationException)
        threw = true;
    assert(threw);
}

@("null elements are allowed")
unittest
{
    auto list = new CopyOnWriteArrayList!Object;
    list.add(null);
    list.add(new Object);
    assert(list.size == 2);
    assert(list.get(0) is null);
}

@("indexOf, lastIndexOf and contains")
unittest
{
    auto list = new CopyOnWriteArrayList!int([1, 2, 3, 2]);
    assert(list.indexOf(2) == 1);
    assert(list.lastIndexOf(2) == 3);
    assert(list.contains(3));
    assert(!list.contains(9));
}

@("equals and hashCode follow the list contract")
unittest
{
    auto a = new CopyOnWriteArrayList!int([1, 2, 3]);
    auto b = new CopyOnWriteArrayList!int([1, 2, 3]);
    auto c = new CopyOnWriteArrayList!int([1, 2, 4]);
    assert(a == b);
    assert(a.toHash == b.toHash);
    assert(a != c);
}

@("removeIf keeps the surviving elements")
unittest
{
    auto list = new CopyOnWriteArrayList!int([1, 2, 3, 4, 5]);
    assert(list.removeIf((int e) => e % 2 == 0));
    assert(list.toString == "[1, 3, 5]");
    assert(!list.removeIf((int e) => e % 2 == 0));
}

@("sort orders the elements")
unittest
{
    auto list = new CopyOnWriteArrayList!int([3, 1, 2]);
    list.sort(null);
    assert(list.toString == "[1, 2, 3]");
}

@("toArray returns a copy")
unittest
{
    auto list = new CopyOnWriteArrayList!int([1, 2, 3]);
    auto copy = list.toArray;
    copy[0] = 99;
    assert(list.get(0) == 1);
}

@("construction from a collection")
unittest
{
    Collection!int source = new CopyOnWriteArrayList!int([4, 5, 6]);
    auto list = new CopyOnWriteArrayList!int(source);
    assert(list.toString == "[4, 5, 6]");
}

private final class Appender
{
    CopyOnWriteArrayList!int list;
    int count;

    this(CopyOnWriteArrayList!int list, int count)
    {
        this.list = list;
        this.count = count;
    }

    void work()
    {
        foreach (i; 0 .. count)
            list.add(i);
    }
}

@("concurrent appends from several threads")
@system
unittest
{
    import core.thread : Thread;

    auto list = new CopyOnWriteArrayList!int;
    enum threadCount = 4;
    enum perThread = 250;
    Thread[] threads;
    foreach (t; 0 .. threadCount)
    {
        auto appender = new Appender(list, perThread);
        threads ~= new Thread(&appender.work);
    }
    foreach (thread; threads)
        thread.start();
    foreach (thread; threads)
        thread.join();
    assert(list.size == threadCount * perThread);
}
