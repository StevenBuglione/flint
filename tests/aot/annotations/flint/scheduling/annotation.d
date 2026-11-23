/// Fixture for Flint AOT tests: `org.springframework.scheduling.annotation`.
module flint.scheduling.annotation;

@safe:

/// `@Async`.
struct Async
{
    /// Executor bean.
    string value;
}
