/++
One process-wide instance of a class that has no fields, for Java's shared constants such as
`Collections.emptyList()`'s `EMPTY_LIST`. Java hands out one object; building a new one per call costs an allocation
on every call.

A class qualifies only when no class in its hierarchy declares a field (`isStateless`, checked at compile time), so
threads that share the instance share no state of the class's own. The instance is built at compile time into the
data segment (not read-only memory), so druntime's monitor word stays writable for `synchronized`. Private to
`flint:engine-aot`'s callers through `flint.engine.aot.objects`.
+/
module flint.engine.aot.sys.constant;

@safe:

/// Whether no class in `T`'s hierarchy, `Object` excepted, declares a field.
template isStateless(T) if (is(T == class))
{
    static if (is(T == Object))
        enum bool isStateless = true;
    else static if (is(T Bases == super))
        enum bool isStateless = T.tupleof.length == 0 && isStateless!(Bases[0]);
}

/// The one instance of the stateless class `T`, the same object on every call and every thread.
// SAFETY: the instance is built at compile time and never reassigned; T has no fields (isStateless), so sharing it
// across threads shares only druntime's monitor, which druntime synchronizes itself.
@trusted T statelessInstance(T)() nothrow @nogc if (is(T == class) && isStateless!T)
{
    __gshared T instance = new T();
    return instance;
}

unittest
{
    static class Base
    {
        int size() const pure nothrow @nogc @safe
        {
            return 0;
        }
    }

    static final class Empty : Base
    {
    }

    static class Counter
    {
        int count;
    }

    static final class DerivedFromCounter : Counter
    {
    }

    // Positive: the same object every call, of the requested class.
    static assert(isStateless!Empty);
    auto first = statelessInstance!Empty();
    assert(first !is null && first is statelessInstance!Empty() && first.size() == 0);
    assert(typeid(first) is typeid(Empty));
    // Negative: a class with a field, or deriving from one, does not qualify.
    static assert(!isStateless!Counter && !isStateless!DerivedFromCounter);
    static assert(!__traits(compiles, statelessInstance!Counter()));
    static assert(!__traits(compiles, statelessInstance!DerivedFromCounter()));
}
