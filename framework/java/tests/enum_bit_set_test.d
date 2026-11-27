module enum_bit_set_test;

import flint.java.lang : UnsupportedOperationException;
import flint.java.util : ArrayList, Collection, LinkedHashSet, List, NoSuchElementException, Set;
import flint.java.util.internal.enumbitset : EnumBitSet;

@safe:

// OpenJDK 21.0.13 (EnumBitSetOracle): Collections.unmodifiableSet(EnumSet.of(...)) iterates in declaration order,
// equals and hashes like any Set with the same members, and throws UnsupportedOperationException from every mutator,
// even one that would change nothing.

private enum E
{
    A,
    B,
    C,
}

private enum Sparse
{
    low = -3,
    high = 40,
}

private bool unsupported(scope void delegate() @safe operation)
{
    try
        operation();
    catch (UnsupportedOperationException)
        return true;
    return false;
}

unittest
{
    Set!E set = EnumBitSet!E.of(E.C, E.A, E.C);
    assert(set.toString() == "[A, C]", set.toString());
    assert(set.size() == 2 && !set.isEmpty() && set.contains(E.A) && !set.contains(E.B));
    assert(set.toArray() == [E.A, E.C]);
    E[] seen;
    foreach (e; set)
        seen ~= e;
    assert(seen == [E.A, E.C]);

    Set!E empty = EnumBitSet!E.of();
    assert(empty.toString() == "[]" && empty.isEmpty() && empty.size() == 0 && empty.hashCode() == 0);
    assert(!set.contains(cast(E) 7));
}

unittest
{
    Set!E set = EnumBitSet!E.of(E.C, E.A);
    auto linked = new LinkedHashSet!E([E.C, E.A]);
    assert(set.equals(linked) && linked.equals(cast(Object) set));
    assert(set.hashCode() == linked.hashCode());
    assert(set.equals(cast(Object) Set!E.of(E.A, E.C)) && !set.equals(cast(Object) Set!E.of(E.A)));
    assert(set.equals(cast(Object) EnumBitSet!E.of(E.A, E.C)) && !set.equals(cast(Object) EnumBitSet!E.of(E.A)));
    assert(set.containsAll(List!E.of(E.A)) && !set.containsAll(List!E.of(E.A, E.B)));
    assert(set.containsAll(EnumBitSet!E.of(E.C)) && !set.containsAll(EnumBitSet!E.of(E.B)));
}

unittest
{
    Set!E set = EnumBitSet!E.of(E.A, E.C);
    Set!E empty = EnumBitSet!E.of();
    Collection!E none = new ArrayList!E();
    assert(unsupported(() { set.add(E.B); }) && unsupported(() { set.add(E.A); }));
    assert(unsupported(() { set.remove(E.A); }) && unsupported(() { set.remove(E.B); }));
    assert(unsupported(() { set.clear(); }) && unsupported(() { empty.clear(); }));
    assert(unsupported(() { set.addAll(none); }) && unsupported(() { set.removeAll(none); }));
    assert(unsupported(() { set.retainAll(List!E.of(E.A, E.C)); }));
    assert(unsupported(() { set.removeIf((E) => false); }));
    assert(set.size() == 2);

    auto it = set.iterator();
    assert(it.next() == E.A);
    assert(unsupported(() { it.remove(); }));
    assert(it.next() == E.C && !it.hasNext());
    bool ended;
    try
        it.next();
    catch (NoSuchElementException)
        ended = true;
    assert(ended);
}

unittest
{
    // Members are numbered by declaration, not by value.
    Set!Sparse set = EnumBitSet!Sparse.of(Sparse.high, Sparse.low);
    assert(set.toArray() == [Sparse.low, Sparse.high] && set.size() == 2);
    assert(!set.contains(cast(Sparse) 0));
}
