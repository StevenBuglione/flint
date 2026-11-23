/// Fixture for Flint AOT tests until flint-security exists: `org.springframework.security.access.prepost`.
module flint.security.access.prepost;

@safe:

/// `@PreAuthorize`.
struct PreAuthorize
{
    /// SpEL expression.
    string value;
}
