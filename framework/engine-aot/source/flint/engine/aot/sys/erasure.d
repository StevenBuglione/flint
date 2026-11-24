/++
Views for Java-style erased collections: a collection of class `T` keeps its elements as `Object` references in one
non-template implementation, and a thin typed facade hands them back as `T`. A class reference is the object's
address whatever static class it is typed as, so the view is a reinterpretation, not a dynamic cast per element.
Interfaces do not qualify: an interface reference is not the object's address. Private to `flint:engine-aot`'s
callers through `flint.engine.aot.objects`.

The caller's obligation: every element viewed as `T` is null or an instance of `T` (or a subclass), because every
path that stores into the erased storage takes a `T`. Debug builds check it.
+/
module flint.engine.aot.sys.erasure;

@safe:

/// `o`, known to be null or an instance of class `T`, as a `T`, without a dynamic cast.
// SAFETY: a class reference is the object's address under any static class type; the caller stores only Ts.
@trusted inout(T) assumeClass(T)(inout(Object) o) pure nothrow @nogc if (is(T == class))
{
    debug assert(o is null || cast(inout(T)) o !is null, "an erased collection holds an element of another class");
    return cast(inout(T)) cast(inout(void)*) o;
}

/// `items`, known to hold only nulls and instances of class `T`, viewed as `T[]`: the same memory, no copy.
// SAFETY: T[] and Object[] have one layout (object addresses); the caller stores only Ts into the storage.
@trusted inout(T)[] assumeClasses(T)(inout(Object)[] items) pure nothrow @nogc if (is(T == class))
{
    return cast(inout(T)[]) items;
}

/// `items`, an array of class `T` the caller owns, viewed as `Object[]` storage: the same memory, no copy.
// SAFETY: one layout; the caller owns `items` and keeps the storage's only-Ts invariant from then on.
@trusted Object[] asObjects(T)(T[] items) pure nothrow @nogc if (is(T == class))
{
    return cast(Object[]) items;
}

unittest
{
    static class Animal
    {
        string name;
        this(string name) pure nothrow
        {
            this.name = name;
        }
    }

    static final class Cat : Animal
    {
        this(string name) pure nothrow
        {
            super(name);
        }
    }

    static interface Named
    {
    }

    // Positive: an element, a subclass instance and null round-trip; arrays view the same memory both ways.
    Object[] storage = [new Animal("a"), new Cat("c"), null];
    assert(assumeClass!Animal(storage[0]).name == "a" && assumeClass!Animal(storage[1]).name == "c");
    assert(assumeClass!Animal(storage[2]) is null);
    auto animals = assumeClasses!Animal(storage);
    assert(animals.length == 3 && animals[1].name == "c");
    assert(cast(const(void)*)&animals[0] is cast(const(void)*)&storage[0]);
    auto cats = [new Cat("x")];
    auto objects = asObjects(cats);
    assert(objects.length == 1 && objects[0] is cats[0]);
    // Negative: interfaces and non-class types do not qualify.
    static assert(!__traits(compiles, assumeClass!Named(storage[0])));
    static assert(!__traits(compiles, assumeClasses!int(storage)));
    static assert(!__traits(compiles, asObjects([1, 2])));
}
