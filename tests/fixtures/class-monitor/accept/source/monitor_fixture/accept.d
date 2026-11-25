/// FLINT-E0536 fixture: none of this gives class metadata a GC-allocated monitor.
module monitor_fixture.accept;

import core.sync.mutex : Mutex;

@system:

/// A class whose metadata is synchronized on.
final class Foo
{
}

/// An ordinary object to share a mutex with.
final class Resource
{
}

/// Dedicated mutexes, ordinary objects and `synchronized (typeid(X))` (a calloc'ed monitor) all pass.
Object[] accept(Object owner, Resource resource)
{
    Object[] made;
    made ~= new Mutex();
    made ~= cast(Object) new shared Mutex();
    made ~= new Mutex(owner);
    made ~= new Mutex(resource);
    made ~= new Mutex(null);
    synchronized (typeid(Foo))
    {
        // A metadata object's own monitor comes from the C heap.
    }
    synchronized (Foo.classinfo)
    {
        // Likewise.
    }
    setSameMutex(cast(shared) resource, cast(shared) typeid(Foo));
    return made;
}
