/// Fixture for Flint AOT tests: the spring-core annotation shapes of docs/spring/aot-contract.md section 2.
module flint.core.annotation;

@safe:

/// A `Class`-valued annotation attribute: the fully qualified D name (aot-contract.md section 2, rule R4.1).
struct ClassRef
{
    /// Fully qualified D name.
    string name;
}

/// `T.class` in an annotation attribute.
enum ClassRef classOf(T) = ClassRef(__traits(fullyQualifiedName, T));

/// `@AliasFor`.
struct AliasFor
{
    /// The aliased attribute; alias of `value`.
    string attribute;
    /// The meta-annotation that declares it; `ClassRef.init` means this annotation.
    ClassRef annotation;
    /// Alias of `attribute`.
    string value;
}

/// `@Order`.
struct Order
{
    /// Order value; lower runs first.
    int value = int.max;
}
