/// Fixture for Flint AOT tests: `org.springframework.security.access.prepost`.
module flint.security.access.prepost;

@safe:

/// `@PreAuthorize`.
struct PreAuthorize
{
    /// SpEL expression.
    string value;
}
