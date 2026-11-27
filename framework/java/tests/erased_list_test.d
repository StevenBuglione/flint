/++
Flint's tests of the erased collections of a class (playbook B-1): `ArrayList!T`, `List.of`, `Collections.emptyList`,
`singletonList`, `unmodifiableList`, `HashSet!T` and `LinkedHashSet!T` (and so every map's `entrySet`) for a class
`T` share one `Object` implementation and must behave exactly as the template collections do for other elements.
+/
module flint.java.erased_list_test;

import core.memory : GC;
import flint.engine.aot.any : Any, AnyTypeException;
import flint.engine.aot.name : typeNameOf;
import flint.java.lang : ClassCastException, IllegalStateException, IndexOutOfBoundsException,
    UnsupportedOperationException;
import flint.java.util : AbstractList, ArrayList, Collection, Collections, Comparator, HashMap, HashSet,
    ErasedArrayList, Iterator, LinkedHashSet, List, MapEntry, NoSuchElementException, RawCollection, Set;

@safe:

private class Pet
{
    string name;
    int age;

    this(string name, int age = 0) pure nothrow
    {
        this.name = name;
        this.age = age;
    }

    // Java's equals and hashCode by name; hashCode is the class's own method, not Object.toHash.
    override bool opEquals(Object o)
    {
        auto that = cast(Pet) o;
        return that !is null && that.name == name;
    }

    override size_t toHash() @safe nothrow
    {
        return 7;
    }

    int hashCode()
    {
        return cast(int) name.length;
    }

    int compareTo(Pet other)
    {
        return age - other.age;
    }

    override string toString() const
    {
        return name;
    }
}

private final class Cat : Pet
{
    this(string name, int age = 0) pure nothrow
    {
        super(name, age);
    }
}

private class Plain
{
}

private T expectThrow(E, T)(scope T delegate() @safe action)
{
    try
        action();
    catch (E)
        return T.init;
    assert(false, "expected " ~ E.stringof);
}

@("ArrayList of a class: positional access, search, mutation and iteration")
unittest
{
    auto list = new ArrayList!Pet();
    assert(list.isEmpty() && list.size() == 0 && list.toString() == "[]");
    list.add(new Pet("rex", 3));
    list.add(new Cat("tom", 1));
    list.add(0, new Pet("ace", 2));
    assert(list.size() == 3 && list.get(0).name == "ace");
    assert(list.getFirst().name == "ace" && list.getLast().name == "tom");
    assert(list.toString() == "[ace, rex, tom]");
    // Search uses Java equals (by name here), not identity.
    assert(list.contains(new Pet("rex")) && list.indexOf(new Pet("tom")) == 2 && list.indexOf(new Pet("zed")) == -1);
    list.add(new Pet("rex", 9));
    assert(list.lastIndexOf(new Pet("rex")) == 3);
    assert(list.set(3, new Pet("max")).age == 9 && list.get(3).name == "max");
    assert(list.remove(new Pet("max")) && !list.remove(new Pet("max")));
    assert(list.removeAt(0).name == "ace" && list.remove(0).name == "rex" && list.size() == 1);
    expectThrow!IndexOutOfBoundsException(() @safe => list.get(5));
    expectThrow!IndexOutOfBoundsException(() @safe { list.add(9, new Pet("x")); return 0; });
    // Iteration: foreach, forEach and an iterator that removes.
    list.add(new Pet("a"));
    list.add(new Pet("b"));
    string names;
    foreach (pet; list)
        names ~= pet.name;
    list.forEach((Pet p) { names ~= p.name; });
    assert(names == "tomabtomab");
    auto it = list.iterator();
    it.next();
    it.remove();
    assert(list.toString() == "[a, b]");
    expectThrow!IllegalStateException(() @safe { it.remove(); return 0; });
    list.clear();
    assert(list.isEmpty());
    expectThrow!NoSuchElementException(() @safe => list.getFirst());
}

@("ArrayList of a class: bulk operations, sublists, arrays, streams and boxing")
unittest
{
    auto list = new ArrayList!Pet([new Pet("a", 3), new Pet("b", 1), new Pet("c", 2)]);
    auto other = new ArrayList!Pet(cast(Collection!Pet) list);
    assert(other.equals(list) && list.equals(other) && other !is list);
    assert(list.containsAll(new ArrayList!Pet([new Pet("c"), new Pet("a")])));
    assert(list.subList(1, 3).toString() == "[b, c]");
    expectThrow!IndexOutOfBoundsException(() @safe => list.subList(2, 1));
    assert(list.toArray().length == 3 && list.toArray()[1].name == "b");
    assert(list.addAll(new ArrayList!Pet([new Pet("d")])) && list.size() == 4);
    assert(list.removeAll(new ArrayList!Pet([new Pet("d"), new Pet("a")])) && list.toString() == "[b, c]");
    assert(list.retainAll(new ArrayList!Pet([new Pet("c")])) && list.toString() == "[c]");
    assert(!list.removeIf((Pet p) => p.name == "zzz") && list.removeIf((Pet p) => p.name == "c") && list.isEmpty());
    // Boxing for descriptor engines keeps the element type's name.
    RawCollection raw = new ArrayList!Pet([new Cat("t")]);
    auto boxed = raw.toAnyArray();
    assert(boxed.length == 1 && boxed[0].typeName == typeNameOf!Pet && boxed[0].get!Pet.name == "t");
    assert(raw.elementTypeName() == typeNameOf!Pet && !raw.isSet());
    raw.addAny(Any.of(new Pet("u")));
    assert(raw.size() == 2);
    // A stream of the elements.
    auto pets = new ArrayList!Pet([new Pet("x", 1), new Pet("y", 2)]);
    assert(pets.stream().count() == 2);
}

@("ArrayList of a class: sort by a comparator or by compareTo, stable; hashCode uses the class's own hashCode")
unittest
{
    auto list = new ArrayList!Pet([new Pet("b", 2), new Pet("a", 1), new Pet("c", 2), new Pet("d", 0)]);
    list.sort(null); // compareTo: by age, stable
    assert(list.toString() == "[d, a, b, c]");
    list.sort(Comparator!Pet.comparing((Pet p) => p.name).reversed());
    assert(list.toString() == "[d, c, b, a]");
    // 31 * h + hashCode(e) from 1, with Pet's own hashCode (name length), as the template lists compute it.
    auto two = new ArrayList!Pet([new Pet("ab"), new Pet("xyz")]);
    assert(two.hashCode() == 31 * (31 * 1 + 2) + 3);
    // A class without compareTo cannot be sorted naturally, as in Java.
    auto plain = new ArrayList!Plain([new Plain, new Plain]);
    expectThrow!ClassCastException(() @safe { plain.sort(null); return 0; });
    // Equality is element-wise Java equals, through List!T, and opEquals follows it.
    assert(new ArrayList!Pet([new Pet("q")]) == new ArrayList!Pet([new Pet("q", 5)]));
    assert(!new ArrayList!Pet([new Pet("q")]).equals(new ArrayList!Pet()));
    auto self = new ArrayList!Object();
    self.add(self);
    assert(self.toString() == "[(this Collection)]");
}

// Every mutator of an unmodifiable list throws UnsupportedOperationException.
private void assertUnmodifiable(List!Pet list)
{
    expectThrow!UnsupportedOperationException(() @safe => list.add(new Pet("n")));
    expectThrow!UnsupportedOperationException(() @safe => list.set(0, new Pet("n")));
    expectThrow!UnsupportedOperationException(() @safe => list.removeAt(0));
    expectThrow!UnsupportedOperationException(() @safe => list.remove(new Pet("a")));
    expectThrow!UnsupportedOperationException(() @safe { list.clear(); return 0; });
    expectThrow!UnsupportedOperationException(() @safe => list.removeIf((Pet p) => true));
    expectThrow!UnsupportedOperationException(() @safe { list.sort(null); return 0; });
}

@("Unmodifiable lists of a class: List.of, copyOf, emptyList, singletonList and unmodifiableList")
unittest
{
    auto of = List!Pet.of(new Pet("a"), new Pet("b"));
    auto empty = Collections.emptyList!Pet();
    auto single = Collections.singletonList(new Pet("s"));
    auto backing = new ArrayList!Pet([new Pet("x")]);
    auto view = Collections.unmodifiableList!Pet(backing);
    assert(of.toString() == "[a, b]" && empty.size() == 0 && single.get(0).name == "s" && view.get(0).name == "x");
    assert(empty is Collections.emptyList!Pet());
    // Java's List.of() is one shared empty list, like EMPTY_LIST.
    assert(List!Pet.of() is List!Pet.of() && List!Pet.of().size() == 0 && List!Pet.of().equals(cast(Object) empty));
    assertUnmodifiable(List!Pet.of());
    assert(List!int.of() is List!int.of() && List!int.of().size() == 0 && List!int.of(1).size() == 1);
    foreach (list; [of, empty, single, view])
        assertUnmodifiable(list);
    expectThrow!IndexOutOfBoundsException(() @safe => empty.get(0));
    // A view reads through to its backing list; copies do not.
    auto copy = List!Pet.copyOf(backing);
    backing.add(new Pet("y"));
    assert(view.size() == 2 && view.getLast().name == "y" && copy.size() == 1);
    assert(view.equals(backing) && backing.equals(cast(Object) view) && view.hashCode() == backing.hashCode());
    assert(of.contains(new Pet("b")) && of.indexOf(new Pet("b")) == 1 && of.subList(0, 1).toString() == "[a]");
    assert(of.toArray().length == 2 && empty.toArray().length == 0 && view.toArray()[1].name == "y");
    string names;
    foreach (pet; of)
        names ~= pet.name;
    assert(names == "ab");
}

@("HashSet of a class: Java equals and hashCode decide membership; insertion order, iteration, bulk and freeze")
unittest
{
    auto set = new HashSet!Pet();
    assert(set.isEmpty() && set.isSet() && set.toString() == "[]");
    assert(set.add(new Pet("b")) && set.add(new Cat("a")) && !set.add(new Pet("b", 9)), "equal by name: one element");
    assert(set.size() == 2 && set.contains(new Pet("a")) && !set.contains(new Pet("z")));
    assert(set.toString() == "[b, a]");
    string names;
    foreach (pet; set)
        names ~= pet.name;
    set.forEach((Pet p) { names ~= p.name; });
    assert(names == "baba");
    auto it = set.iterator();
    it.next();
    it.remove();
    assert(set.toString() == "[a]" && !set.contains(new Pet("b")));
    expectThrow!IllegalStateException(() @safe { it.remove(); return 0; });
    assert(set.addAll(new ArrayList!Pet([new Pet("c"), new Pet("d"), new Pet("a")])) && set.size() == 3);
    assert(set.removeAll(new ArrayList!Pet([new Pet("c")])) && set.toString() == "[a, d]");
    assert(set.retainAll(new ArrayList!Pet([new Pet("d")])) && set.toString() == "[d]");
    assert(set.remove(new Pet("d")) && !set.remove(new Pet("d")) && set.isEmpty());
}

@("HashSet of a class: equality, Java's set hashCode, boxing, and frozen sets")
unittest
{
    // Equality and Java's set hashCode: the sum of the elements' own hashCode (name length).
    auto one = new LinkedHashSet!Pet([new Pet("ab"), new Pet("xyz")]);
    auto two = new HashSet!Pet(cast(Collection!Pet) new ArrayList!Pet([new Pet("xyz"), new Pet("ab")]));
    assert(one.equals(two) && two.equals(one) && one.hashCode() == 5 && one == two);
    assert(one.toArray().length == 2 && one.toArray()[0].name == "ab" && one.stream().count() == 2);
    RawCollection raw = one;
    assert(raw.toAnyArray()[1].get!Pet.name == "xyz" && raw.elementTypeName() == typeNameOf!Pet && raw.isSet());
    raw.addAny(Any.of(new Pet("q")));
    assert(one.size() == 3);
}

@("Set.of and emptySet of a class are frozen")
unittest
{
    auto frozen = Set!Pet.of(new Pet("f"));
    expectThrow!UnsupportedOperationException(() @safe => frozen.add(new Pet("g")));
    expectThrow!UnsupportedOperationException(() @safe => frozen.remove(new Pet("f")));
    expectThrow!UnsupportedOperationException(() @safe { frozen.clear(); return 0; });
    expectThrow!UnsupportedOperationException(() @safe => frozen.removeIf((Pet p) => true));
    auto frozenIt = frozen.iterator();
    frozenIt.next();
    expectThrow!UnsupportedOperationException(() @safe { frozenIt.remove(); return 0; });
    assert(Collections.emptySet!Pet().size() == 0 && frozen.contains(new Pet("f")));
}

@("A map's entrySet is an erased set of its entries: order, membership and removal by entry")
unittest
{
    auto map = new HashMap!(string, Pet)();
    map.put("x", new Pet("x"));
    map.put("y", new Pet("y"));
    auto entries = map.entrySet();
    string keys;
    foreach (entry; entries)
        keys ~= entry.getKey() ~ entry.getValue().name;
    assert(keys == "xxyy" && entries.size() == 2);
    auto counts = new HashMap!(string, int)();
    counts.put("a", 1);
    assert(counts.entrySet().toString() == "[a=1]");
}

private interface PrimaryReference
{
    int value();
}

private interface ListReference
{
    int value();
    int hashCode();
}

private extern (C++) interface ForeignReference
{
    int value();
}

private extern (Windows) interface IUnknown
{
    int query();
}

private interface ComReference : IUnknown
{
    int value();
}

private final class ReferenceValue : PrimaryReference, ListReference
{
    int number;

    this(int number)
    {
        this.number = number;
    }

    int value()
    {
        return number;
    }

    int hashCode()
    {
        return 100 + number;
    }

    override bool opEquals(Object other)
    {
        return other is this;
    }

    override size_t toHash() @safe nothrow
    {
        return 1;
    }
}

private final class ReversedReferenceList : ArrayList!ListReference
{
    this(ListReference[] source)
    {
        super(source);
    }

    override ListReference get(int index)
    {
        return super.get(size() - 1 - index);
    }
}

private final class IteratorOverrideList : ArrayList!ListReference
{
    private ListReference yielded;

    this(ListReference stored, ListReference yielded)
    {
        super([stored]);
        this.yielded = yielded;
    }

    override Iterator!ListReference iterator()
    {
        return new ArrayList!ListReference([yielded]).iterator();
    }
}

@("Erased ArrayList explicitly dispatches a custom iterator and keeps inherited indexed reads")
unittest
{
    ListReference stored = new ReferenceValue(2);
    ListReference yielded = new ReferenceValue(3);
    List!ListReference list = new IteratorOverrideList(stored, yielded);

    assert(list.iterator().next() is yielded);
    auto viewCursor = Collections.unmodifiableList(list).iterator();
    assert(viewCursor.next() is yielded);
    expectThrow!UnsupportedOperationException(() @safe { viewCursor.remove(); return 0; });
    list.forEach((ListReference value) { assert(value is stored); });
    foreach (value; list)
        assert(value is stored);
    assert(list.toAnyArray()[0].get!ListReference is stored);
    assert(list.remove(stored) && list.isEmpty());
}

@("Native interface lists share erased array storage and adjust references at typed boundaries")
unittest
{
    static assert(is(ArrayList!ListReference : ErasedArrayList),
            "native interface ArrayList should reuse erased storage");
    static assert(is(ArrayList!Pet : ErasedArrayList));
    static assert(!__traits(compiles, {
            AbstractList!ListReference invalid = new ArrayList!ListReference();
        }));
    static assert(!__traits(compiles, { AbstractList!Pet invalid = new ArrayList!Pet(); }));
    static assert(!is(ArrayList!int : ErasedArrayList));
    static assert(__traits(getLinkage, ForeignReference) != "D");
    static assert(__traits(getLinkage, ComReference) != "D");

    auto owner = new ReferenceValue(2);
    ListReference first = owner;
    ListReference second = new ReferenceValue(3);
    ListReference[] input = [first];
    auto list = new ArrayList!ListReference(input);
    auto view = Collections.unmodifiableList!ListReference(list);
    auto snapshot = List!ListReference.of(input);
    input[0] = second;
    assert(list.get(0) is first && snapshot.get(0) is first);
    assert(cast(Object) list.get(0) is owner);
    assert(cast(AbstractList!ListReference) cast(Object) list is null);
    try
    {
        list.get(-1);
        assert(false, "expected the index check to throw");
    }
    catch (IndexOutOfBoundsException failure)
        assert(failure.getMessage() == "Index -1 out of bounds for length 1");
    try
    {
        list.add(2, first);
        assert(false, "expected the insertion index check to throw");
    }
    catch (IndexOutOfBoundsException failure)
        assert(failure.getMessage() == "Index: 2, Size: 1");

    RawCollection raw = list;
    raw.addAny(Any.of(second));
    list.add(1, cast(ListReference) null);
    assert(list.contains(null) && list.get(1) is null);
    assert(raw.toAnyArray()[2].get!ListReference is second);
    expectThrow!AnyTypeException(() @safe { raw.addAny(Any.of(new Plain)); return 0; });
    assert(raw.size() == 3);
    assert(list.set(1, second) is null && view.get(1) is second);
    assert(list.removeAt(2) is second && view.size() == 2);

    auto array = list.toArray();
    assert(array[0] is first && array[1] is second);
    array[0] = null;
    assert(list.get(0) is first);
    assert(list.subList(1, 2).get(0) is second);
    auto copy = List!ListReference.__flintFromElements(List!ListReference.__flintElements(list));
    assert(copy.equals(list) && copy.hashCode() == 31 * (31 + 102) + 103);
    assert(List!ListReference.copyOf(list).get(1) is second);

    int sum;
    auto allocated = GC.stats().allocatedInCurrentThread;
    assert(list.get(0) is first);
    foreach (value; cast(List!ListReference) list)
        sum += value.value();
    assert(sum == 5 && GC.stats().allocatedInCurrentThread == allocated);
    auto action = (ListReference value) { sum += value.value(); };
    allocated = GC.stats().allocatedInCurrentThread;
    list.forEach(action);
    assert(sum == 10 && GC.stats().allocatedInCurrentThread == allocated);
    auto cursor = list.iterator();
    assert(cursor.next() is first);
    cursor.remove();
    assert(list.size() == 1 && cursor.next() is second);
    expectThrow!UnsupportedOperationException(() @safe => view.add(first));

    List!ListReference reversed = new ReversedReferenceList([first, second]);
    assert(reversed.get(0) is second && reversed.iterator().next() is second);
    assert(Collections.unmodifiableList(reversed).get(0) is second);
    assert(reversed.toAnyArray()[0].get!ListReference is second);
    assert(reversed.subList(0, 1).get(0) is second);
}
