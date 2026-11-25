/// FLINT-E0536 fixture: every line marked `expect: FLINT-E0536` gives class metadata a GC-allocated monitor.
module monitor_fixture.reject;

import core.sync.mutex : Mutex, Lock = Mutex;

@system:

/// A class whose metadata the fixture misuses.
final class Foo
{
}

/// Holds a ClassInfo in a field.
final class Holder
{
    /// The metadata of some class.
    TypeInfo_Class info;

    /// A method returning ClassInfo.
    ClassInfo meta()
    {
        return typeid(Foo);
    }

    /// An inferred return type.
    auto inferred()
    {
        return Foo.classinfo;
    }
}

/// A function returning ClassInfo.
ClassInfo metadataOf()
{
    return typeid(Foo);
}

/// The type of the argument comes only from the compiler: through locals, parameters, fields and results.
Object[] reject(TypeInfo_Class parameter, Holder holder, Object owner)
{
    Object[] made;
    made ~= new Mutex(typeid(Foo)); // expect: FLINT-E0536
    made ~= new Mutex(Foo.classinfo); // expect: FLINT-E0536
    auto local = typeid(Foo);
    made ~= new Mutex(local); // expect: FLINT-E0536
    made ~= new Mutex(parameter); // expect: FLINT-E0536
    made ~= new Mutex(holder.info); // expect: FLINT-E0536
    made ~= new Mutex(metadataOf()); // expect: FLINT-E0536
    made ~= new Mutex(holder.meta()); // expect: FLINT-E0536
    made ~= new Mutex(holder.inferred); // expect: FLINT-E0536
    made ~= new Lock(typeid(Foo)); // expect: FLINT-E0536
    made ~= new Mutex(cast(TypeInfo) owner); // expect: FLINT-E0536
    made ~= cast(Object) new shared Mutex(typeid(Foo)); // expect: FLINT-E0536
    setSameMutex(cast(shared) typeid(Foo), cast(shared) owner); // expect: FLINT-E0536
    (cast(shared) local).setSameMutex(cast(shared) owner); // expect: FLINT-E0536
    return made;
}

/// A template instantiated here is checked at its instantiation.
Object lockMetadata(T)()
{
    return new Mutex(typeid(T)); // expect: FLINT-E0536
}

/// Instantiates the template.
Object instantiate()
{
    return lockMetadata!Foo();
}

/// Writing a monitor word directly.
void raw(Object target)
{
    target.__monitor = null; // expect: FLINT-E0536
}
