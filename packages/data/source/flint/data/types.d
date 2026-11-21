/// Static repository annotations and value types.
module flint.data.types;

@safe:

/// SQL table identifier for an entity.
struct Table
{
    /// Unqualified identifier.
    string name;
}

/// Marks the entity's sole integer identifier.
struct Id
{
}

/// Overrides a field's SQL column name.
struct Column
{
    /// Unqualified identifier.
    string name;
}

/// Named-parameter SQL for a generated repository query.
struct Query
{
    /// Read-only SQL returning named projection aliases.
    string sql;
}

/// Marks the integer used for optimistic concurrency.
struct Version
{
}

/// Includes a field when reading rows and excludes it from persistence.
struct ReadOnly
{
}

/// A value that can represent SQL NULL independently of its scalar default.
struct Nullable(T)
{
    /// Whether the cell has a non-null value.
    bool present;
    /// Contents when present.
    T value;
}

/// Requested pagination in the owned collection profile.
struct PageRequest
{
    /// Maximum items on a page.
    uint limit = 100;
    /// Starting item index.
    ulong offset;
}

/// An owned collection profile outside the hot repository contract.
struct Page(T)
{
    /// Items in order.
    T[] items;
    /// Whether further results exist.
    bool hasMore;
}
