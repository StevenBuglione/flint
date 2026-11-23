/++
Interim conformance copy of `flint.engine.aot.any` (docs/spring/aot-contract.md section 4.1, contract 1).
framework-core owns the real module; this copy implements the contract only as far as the web packages need
and is deleted when `flint:engine-aot` lands.

Deviation from the contract while interim: `get!T` returns by value, not by `ref`.
+/
module flint.engine.aot.any;

@safe:

/// Thrown by `Any.get!T` when the boxed value is not a `T`.
class AnyTypeException : Exception
{
    ///
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow @nogc
    {
        super(message, file, line);
    }
}

/// An erased value for Object-typed APIs: the value's type name and the value.
struct Any
{
    private Object reference;      // class and interface values
    private const(void)[] payload; // a GC copy of any other value
    private TypeInfo type;
    private string name;

    /// Boxes a copy of `value`.
    static Any of(T)(T value) @trusted
    {
        // SAFETY: the payload is a fresh GC copy owned by this Any; `get` reads it back only as the same type.
        Any result;
        result.name = __traits(fullyQualifiedName, T);
        static if (is(T == class) || is(T == interface))
        {
            result.reference = cast(Object) cast() value;
            result.type = typeid(T);
        }
        else
        {
            auto copy = new Unqual!T[1];
            copy[0] = cast(Unqual!T) value;
            result.payload = copy;
            result.type = typeid(Unqual!T);
        }
        return result;
    }

    /++
    The boxed value as a `T`: the exact type, a `const` view, or a base class or interface of a boxed class.
    Throws: `AnyTypeException` on a mismatch.
    +/
    T get(T)() const @trusted
    {
        // SAFETY: the payload was written by `of!U` with typeid(U) == typeid(Unqual!T), checked first.
        static if (is(T == class) || is(T == interface))
        {
            if (reference is null && payload is null)
                return null;
            auto cast_ = cast(T) cast() reference;
            if (cast_ is null)
                throw new AnyTypeException("Any holds " ~ name ~ ", not " ~ __traits(fullyQualifiedName, T));
            return cast_;
        }
        else
        {
            if (type !is typeid(Unqual!T) && type != typeid(Unqual!T))
                throw new AnyTypeException("Any holds " ~ (name is null ? "nothing" : name) ~ ", not "
                        ~ __traits(fullyQualifiedName, T));
            return (cast(const(Unqual!T)[]) payload)[0];
        }
    }

    /// Whether the boxed value is a `T` (or, for classes, derives from it).
    bool isA(T)() const @trusted
    {
        // SAFETY: only compares type identities.
        static if (is(T == class) || is(T == interface))
            return reference !is null && (cast(T) cast() reference) !is null;
        else
            return type !is null && (type is typeid(Unqual!T) || type == typeid(Unqual!T));
    }

    /// `Any.init`, or a null class or array.
    bool isNull() const nothrow @nogc
    {
        if (type is null)
            return true;
        if (payload is null)
            return reference is null;
        return false;
    }

    /// The fully qualified D name of the boxed type, or `null`.
    string typeName() const nothrow @nogc
    {
        return name;
    }

    /// The boxed class reference, or `null`.
    Object asObject() nothrow @nogc
    {
        return reference;
    }

    /// The runtime type of the boxed value (the dynamic class for class references).
    package(flint) TypeInfo runtimeType() const nothrow @trusted
    {
        // SAFETY: typeid on a live Object only reads its vtable.
        return reference !is null ? typeid(cast() reference) : cast() type;
    }
}

private template Unqual(T)
{
    static if (is(T U == immutable U))
        alias Unqual = U;
    else static if (is(T U == const U))
        alias Unqual = U;
    else static if (is(T U == shared U))
        alias Unqual = U;
    else
        alias Unqual = T;
}
