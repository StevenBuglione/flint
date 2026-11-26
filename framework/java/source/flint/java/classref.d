/++
Java's `Class<?>` where an annotation attribute names a type: the type's canonical fully qualified D name
(AOT contract section 2). Rulebook R4 makes `Class` parameters template parameters; annotation attributes cannot be
templates, so they carry a `ClassRef`. A leaf module: annotation-only clients import it without `flint.java.lang`'s
graph (about 440 template instances); `flint.java.lang` and `flint.core.annotation` re-export it.
+/
module flint.java.classref;

@safe:

/// Java's `Class<?>` in an annotation attribute.
struct ClassRef
{
    /// The canonical fully qualified D name; empty for `ClassRef.init` ("none", or "this annotation").
    string name;

    /// The stored canonical name, or "null" for an unset reference.
    string toString() const pure nothrow @nogc
    {
        return name.length == 0 ? "null" : name;
    }
}

/// Java's `T.class` in an annotation attribute: `@ConditionalOnMissingBean(classOf!DataSource)`.
enum ClassRef classOf(T) = ClassRef(imported!"flint.engine.aot.name".typeNameOf!T);

unittest
{
    static struct Sample
    {
    }

    assert(classOf!Sample.name == imported!"flint.engine.aot.name".typeNameOf!Sample && ClassRef.init.name is null);
}
