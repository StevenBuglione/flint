/// Fixture for Flint AOT tests: `org.springframework.resilience.annotation`.
module flint.resilience.annotation;

@safe:

/// `@Retryable`.
struct Retryable
{
    /// Maximum retries.
    long maxRetries = 3;
}
