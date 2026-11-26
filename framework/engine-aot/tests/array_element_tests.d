module flint.engine.aot.array_element_tests;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : ElementWriteResult, descriptorOf;

@safe:

@("array element writes preserve aliases and report errors before mutation")
unittest
{
    auto values = [1, 2, 3];
    auto receiver = Any.of(values);
    const aliasBox = Any.of(values);
    alias Write = ElementWriteResult function(ref Any, size_t, Any) @safe nothrow @nogc;
    const Write write = descriptorOf!(int[]).setElement;
    assert(write !is null);

    assert(write(receiver, 1, Any.of(8)) == ElementWriteResult.written);
    assert(values == [1, 8, 3] && aliasBox.get!(int[]) == [1, 8, 3]);
    assert(write(receiver, values.length, Any.of(9)) == ElementWriteResult.outOfBounds);
    assert(write(receiver, size_t.max, Any.of(9)) == ElementWriteResult.outOfBounds);
    assert(write(receiver, 1, Any.of(9L)) == ElementWriteResult.wrongElement);
    assert(write(receiver, 1, Any.init) == ElementWriteResult.wrongElement);
    assert(values == [1, 8, 3] && aliasBox.get!(int[]) == values);

    auto wrongReceiver = Any.of([1L]);
    assert(write(wrongReceiver, 0, Any.of(4)) == ElementWriteResult.wrongReceiver);
    auto absent = Any.of(cast(int[]) null);
    assert(write(absent, 0, Any.of(4)) == ElementWriteResult.wrongReceiver);
    assert(ElementWriteResult.init != ElementWriteResult.written);
}

private interface Animal
{
}

private class Dog : Animal
{
}

private class Plant
{
}

@("array element writes accept compatible references and typed inline or boxed values")
unittest
{
    auto animals = new Animal[1];
    auto receiver = Any.of(animals);
    auto setAnimal = descriptorOf!(Animal[]).setElement;
    auto dog = new Dog;
    assert(setAnimal(receiver, 0, Any.of(dog)) == ElementWriteResult.written);
    assert(animals[0] is dog);
    assert(setAnimal(receiver, 0, Any.of(new Plant)) == ElementWriteResult.wrongElement);
    assert(animals[0] is dog);
    assert(setAnimal(receiver, 0, Any.init) == ElementWriteResult.written);
    assert(animals[0] is null);

    static struct Inline
    {
        int value;
    }

    static struct Boxed
    {
        long[8] values;
    }

    auto small = new Inline[1];
    auto wrapped = Any.of(small);
    assert(descriptorOf!(Inline[]).setElement(wrapped, 0, Any.of(Inline(7))) == ElementWriteResult.written);
    assert(small[0].value == 7);

    auto large = new Boxed[1];
    auto boxed = Any.of(large);
    Boxed item;
    item.values[7] = 12;
    assert(descriptorOf!(Boxed[]).setElement(boxed, 0, Any.of(item)) == ElementWriteResult.written);
    assert(large[0].values[7] == 12);

    auto nested = new int[][1];
    auto nestedReceiver = Any.of(nested[]);
    auto setNested = descriptorOf!(int[][]).setElement;
    auto child = [42];
    assert(setNested(nestedReceiver, 0, Any.of(child)) == ElementWriteResult.written);
    assert(nested[0] is child);
    assert(setNested(nestedReceiver, 0, Any.init) == ElementWriteResult.written);
    assert(nested[0] is null);
}

@("read-only and non-slice descriptors have no setter")
unittest
{
    assert(descriptorOf!(const(int)[]).setElement is null);
    assert(descriptorOf!(immutable(int)[]).setElement is null);
    assert(descriptorOf!(const(int[])).setElement is null);
    assert(descriptorOf!(immutable(int[])).setElement is null);
    assert(descriptorOf!(int[2]).setElement is null);
    assert(descriptorOf!string.setElement is null);
    assert(descriptorOf!(int[string]).setElement is null);
}
