/// Fixture for Flint AOT tests: `org.springframework.data.repository`.
module flint.data.repository;

@safe:

/// `Repository<T, ID>`.
interface Repository(T, ID)
{
}

/// `CrudRepository<T, ID>`.
interface CrudRepository(T, ID) : Repository!(T, ID)
{
    /// Count all.
    long count();
}

/// `@Query`.
struct Query
{
    /// SQL.
    string value;
}
