module copyonwritearrayset_test;

import flint.java.util : Collection, Iterator;
import flint.java.util.concurrent.copyonwritearraylist : CopyOnWriteArrayList;
import flint.java.util.concurrent.copyonwritearrayset : CopyOnWriteArraySet;

@safe:

private CopyOnWriteArraySet!int intSet(int[] values)
{
    return new CopyOnWriteArraySet!int(new CopyOnWriteArrayList!int(values));
}

@("empty construction and size")
unittest
{
    auto set = new CopyOnWriteArraySet!int;
    assert(set.size == 0);
    assert(set.isEmpty);
    assert(set.toString == "[]");
    assert(set.isSet);
}

@("add rejects duplicates")
unittest
{
    auto set = new CopyOnWriteArraySet!int;
    assert(set.add(1));
    assert(!set.add(1));
    assert(set.add(2));
    assert(set.size == 2);
    assert(set.contains(1));
    assert(!set.contains(9));
}

@("add after remove re-adds the element")
unittest
{
    auto set = new CopyOnWriteArraySet!int;
    assert(set.add(1));
    assert(!set.add(1));
    assert(set.remove(1));
    assert(set.add(1));
    assert(set.toString == "[1]");
}

@("addAll keeps the set distinct")
unittest
{
    auto set = intSet([1, 2]);
    Collection!int source = new CopyOnWriteArrayList!int([2, 3, 4]);
    assert(set.addAll(source));
    assert(set.toString == "[1, 2, 3, 4]");
    Collection!int again = new CopyOnWriteArrayList!int([1, 2, 3, 4]);
    assert(!set.addAll(again));
}

@("construction from a collection keeps the first occurrence of each element")
unittest
{
    Collection!int source = new CopyOnWriteArrayList!int([3, 1, 3, 2, 1]);
    auto set = new CopyOnWriteArraySet!int(source);
    assert(set.size == 3);
    assert(set.toString == "[3, 1, 2]");
}

@("remove, removeAll and retainAll")
unittest
{
    auto set = intSet([1, 2, 3, 4, 5]);
    assert(set.remove(2));
    assert(!set.remove(42));
    assert(set.toString == "[1, 3, 4, 5]");
    Collection!int remove = new CopyOnWriteArrayList!int([1, 4]);
    assert(set.removeAll(remove));
    assert(set.toString == "[3, 5]");
    Collection!int keep = new CopyOnWriteArrayList!int([3]);
    assert(set.retainAll(keep));
    assert(set.toString == "[3]");
}

@("removeIf keeps the surviving elements")
unittest
{
    auto set = intSet([1, 2, 3, 4, 5]);
    assert(set.removeIf((int e) => e % 2 == 0));
    assert(set.toString == "[1, 3, 5]");
    assert(!set.removeIf((int e) => e % 2 == 0));
}

@("iterator is a snapshot")
unittest
{
    auto set = intSet([1, 2, 3]);
    Iterator!int iterator = set.iterator();
    set.add(4);
    int[] seen;
    while (iterator.hasNext)
        seen ~= iterator.next();
    assert(seen == [1, 2, 3]);
}

@("equals and hashCode follow the set contract")
unittest
{
    auto a = intSet([1, 2, 3]);
    auto b = intSet([3, 2, 1]);
    auto c = intSet([1, 2, 4]);
    assert(a == b);
    assert(a.toHash == b.toHash);
    assert(a != c);
}

@("toString and toArray")
unittest
{
    auto set = intSet([1, 2, 3]);
    auto copy = set.toArray;
    copy[0] = 99;
    assert(set.contains(1));
    assert(set.toString == "[1, 2, 3]");
}

@("null elements are allowed")
unittest
{
    auto set = new CopyOnWriteArraySet!Object;
    assert(set.add(null));
    assert(!set.add(null));
    assert(set.add(new Object));
    assert(set.size == 2);
}
