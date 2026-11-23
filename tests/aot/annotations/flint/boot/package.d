/// Fixture for Flint AOT tests: `org.springframework.boot`, only the ADR-029 alias.
module flint.boot;

@safe:

/// ADR-029's `@FlintApplication`, used as a bare type UDA: an alias of `@FlintBootApplication`.
class FlintApplication
{
}
