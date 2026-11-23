/++
Interim conformance copy of the leaf module `flint.core.annotation` names that docs/spring/aot-contract.md
section 2 defines (`AliasFor`, `ClassRef`, `classOf`), plus `Order`. framework-core owns the real module;
deleted when `flint:core` lands.
+/
module flint.core.annotation;

@safe:

/// A `Class`-valued annotation attribute: the fully qualified D name.
struct ClassRef
{
    string name; ///
}

/// `Foo.class` as an annotation attribute value.
enum ClassRef classOf(T) = ClassRef(__traits(fullyQualifiedName, T));

/// `@AliasFor`.
struct AliasFor
{
    string attribute; ///
    ClassRef annotation; ///
    string value; ///
}

/// `@Order`.
struct Order
{
    int value = int.max; /// Ordered.LOWEST_PRECEDENCE
}
