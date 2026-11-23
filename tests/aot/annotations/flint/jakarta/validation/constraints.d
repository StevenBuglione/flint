/// Fixture for Flint AOT tests: `jakarta.validation.constraints`.
module flint.jakarta.validation.constraints;

@safe:

/// `@NotBlank`.
struct NotBlank
{
    /// Message template.
    string message = "{jakarta.validation.constraints.NotBlank.message}";
}

/// `@Size`.
struct Size
{
    /// Message template.
    string message = "{jakarta.validation.constraints.Size.message}";
    /// Minimum size.
    int min = 0;
    /// Maximum size.
    int max = int.max;
}
