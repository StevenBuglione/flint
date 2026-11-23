/// Fixture for Flint AOT tests: `org.springframework.context.event`.
module flint.context.event;

@safe:

/// `@EventListener`.
struct EventListener
{
    /// SpEL condition.
    string condition;
}
