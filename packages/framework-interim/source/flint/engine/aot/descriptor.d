/++
Interim conformance copy of `flint.engine.aot.descriptor` (docs/spring/aot-contract.md section 4.2,
contract 1), deleted when framework-core's `flint:engine-aot` lands.

Interim addition, proposed to framework-core: `registerDescriptor` and `findDescriptor`, the lookup by
fully qualified name that message conversion needs.
+/
module flint.engine.aot.descriptor;

import flint.engine.aot.any : Any;

@safe:

///
enum TypeKind
{
    scalar,
    string_,
    enum_,
    array,
    struct_,
    class_,
    interface_
}

///
struct MergedAnnotation
{
    string type; /// fully qualified annotation name
    Any value; /// the merged struct literal
    ubyte distance; /// 0 = declared, 1+ = meta-annotation depth
}

///
struct ParameterDescriptor
{
    string name; ///
    string type; ///
    MergedAnnotation[] annotations; ///
}

/// A JSON / binding / validation property.
struct PropertyDescriptor
{
    string name; ///
    string type; ///
    MergedAnnotation[] annotations; ///
    Any function(ref Any self) @safe get; ///
    void function(ref Any self, Any value) @safe set; ///
}

///
struct ConstructorDescriptor
{
    ParameterDescriptor[] parameters; ///
    MergedAnnotation[] annotations; ///
    Any function(scope Any[] arguments) @safe invoke; ///
}

///
struct MethodDescriptor
{
    string name; ///
    string returnType; ///
    ParameterDescriptor[] parameters; ///
    MergedAnnotation[] annotations; ///
    uint index; ///
}

/// Flint AOT's per-type table.
final class Descriptor
{
    string name; ///
    TypeKind kind; ///
    string[] supertypes; ///
    MergedAnnotation[] annotations; ///
    PropertyDescriptor[] properties; ///
    ConstructorDescriptor[] constructors; ///
    MethodDescriptor[] methods; ///
    Any function() @safe create; ///
    string[] enumConstants; ///

    /// The merged annotation of `type`, or `null`.
    const(MergedAnnotation)* annotation(string type) const nothrow @nogc
    {
        foreach (ref candidate; annotations)
            if (candidate.type == type)
                return &candidate;
        return null;
    }
}

private __gshared Descriptor[string] registered;

/// Interim: makes `descriptor` findable by name. Startup only.
void registerDescriptor(Descriptor descriptor) @trusted
{
    // SAFETY: startup-only registration before requests are served; read-only afterwards.
    registered[descriptor.name] = descriptor;
}

/// Interim: the descriptor registered for `name`, or `null`.
Descriptor findDescriptor(string name) nothrow @trusted
{
    // SAFETY: read-only after startup registration.
    if (auto found = name in registered)
        return *found;
    return null;
}
