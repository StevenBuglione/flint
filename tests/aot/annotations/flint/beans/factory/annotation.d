/// Fixture for Flint AOT tests: `org.springframework.beans.factory.annotation`.
module flint.beans.factory.annotation;

@safe:

/// `@Autowired`.
struct Autowired
{
    /// Whether the dependency is required.
    bool required = true;
}

/// `@Qualifier`.
struct Qualifier
{
    /// Qualifier value.
    string value;
}

/// `@Value`.
struct Value
{
    /// Placeholder or expression.
    string value;
}
