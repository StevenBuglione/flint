/// An entity and a repository with derived queries.
module shop.data;

import flint.data.annotation : Id;
import flint.data.relational.core.mapping : Column, Table;
import flint.data.repository : CrudRepository;
import flint.jakarta.validation.constraints : NotBlank, Size;

@safe:

/// An owner's standing.
enum OwnerStatus
{
    active,
    archived
}

/// An owner row.
@Table("owners")
struct Owner
{
    /// Primary key.
    @Id
    long id;
    /// First name.
    @NotBlank
    string firstName;
    /// Last name.
    @NotBlank
    @Size(max : 30)
    @Column("surname")
    string lastName;
    /// City.
    string city;
}

/// Owner queries derived from method names.
interface OwnerRepository : CrudRepository!(Owner, long)
{
    /// By last name, ignoring case, ordered by first name.
    Owner[] findByLastNameIgnoreCaseOrderByFirstNameAsc(string lastName);
    /// The first two in a city.
    Owner[] findFirst2ByCityAndFirstNameStartingWith(string city, string prefix);
    /// Whether any owner lives in a city.
    bool existsByCity(string city);
}
