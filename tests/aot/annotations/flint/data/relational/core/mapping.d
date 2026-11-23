/// Fixture for Flint AOT tests: `org.springframework.data.relational.core.mapping`.
module flint.data.relational.core.mapping;

@safe:

/// `@Table`.
struct Table
{
    /// Table name.
    string value;
}

/// `@Column`.
struct Column
{
    /// Column name.
    string value;
}
