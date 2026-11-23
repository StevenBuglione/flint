/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba, the reference pinned in benchmarks/spring/apps.json):
`org.springframework.samples.petclinic.model`, ported to Flint. Copyright 2002-2013 the original author or authors.
Licensed under the Apache License, Version 2.0.
Modified by the Flint authors:
- Java → D syntax, one module per Java package (R1).
- The JPA mapping annotations are dropped: this port runs the `jdbc` profile only.
- An entity's `Integer id` is an `int`, and 0 marks a new entity (`isNew`), as in Flint AOT's petclinic fixture.
- The `Set`-valued associations are D arrays behind the same `List`-returning accessors.
+/
module org.springframework.samples.petclinic.model;

import flint.java.time : LocalDate;
import flint.java.util : ArrayList, List;

@safe:

/// Simple JavaBean domain object with an id property. Used as a base class for objects needing this property.
class BaseEntity
{
    protected int id;

    ///
    int getId()
    {
        return id;
    }

    ///
    void setId(int id)
    {
        this.id = id;
    }

    /// Whether the entity has not been stored yet.
    bool isNew()
    {
        return id == 0;
    }
}

/// Simple JavaBean domain object adds a name property to `BaseEntity`. Used as a base class for objects needing
/// these properties.
class NamedEntity : BaseEntity
{
    private string name;

    ///
    string getName()
    {
        return name;
    }

    ///
    void setName(string name)
    {
        this.name = name;
    }

    override string toString() const
    {
        return name;
    }
}

/// Simple JavaBean domain object representing an person.
class Person : BaseEntity
{
    protected string firstName;
    protected string lastName;

    ///
    string getFirstName()
    {
        return firstName;
    }

    ///
    void setFirstName(string firstName)
    {
        this.firstName = firstName;
    }

    ///
    string getLastName()
    {
        return lastName;
    }

    ///
    void setLastName(string lastName)
    {
        this.lastName = lastName;
    }
}

/// Simple JavaBean domain object representing an owner.
class Owner : Person
{
    private string address;
    private string city;
    private string telephone;
    private Pet[] pets;

    ///
    string getAddress()
    {
        return address;
    }

    ///
    void setAddress(string address)
    {
        this.address = address;
    }

    ///
    string getCity()
    {
        return city;
    }

    ///
    void setCity(string city)
    {
        this.city = city;
    }

    ///
    string getTelephone()
    {
        return telephone;
    }

    ///
    void setTelephone(string telephone)
    {
        this.telephone = telephone;
    }

    /// The pets, sorted by name, case-insensitively.
    List!Pet getPets()
    {
        return sortedList(pets, (Pet a, Pet b) => compareIgnoreCase(a.getName(), b.getName()) < 0);
    }

    ///
    void setPets(List!Pet pets)
    {
        this.pets = pets is null ? null : pets.toArray();
    }

    ///
    void addPet(Pet pet)
    {
        pets ~= pet;
        pet.setOwner(this);
    }

    /// Return the Pet with the given name, or null if none found for this Owner.
    Pet getPet(string name)
    {
        return getPet(name, false);
    }

    /// Return the Pet with the given name, or null if none found for this Owner; `ignoreNew` skips new pets.
    Pet getPet(string name, bool ignoreNew)
    {
        foreach (pet; pets)
            if ((!ignoreNew || !pet.isNew()) && compareIgnoreCase(pet.getName(), name) == 0)
                return pet;
        return null;
    }

    /// Return the Pet with the given id, or null if none found for this Owner.
    Pet getPet(int petId)
    {
        foreach (pet; pets)
            if (pet.getId() == petId)
                return pet;
        return null;
    }

    override string toString() const
    {
        import flint.engine.aot.text : decimal;

        return "[Owner@" ~ " id = " ~ decimal(long(id)) ~ ", new = " ~ (id == 0
                ? "true" : "false") ~ ", lastName = '" ~ lastName ~ "', firstName = '" ~ firstName
            ~ "', address = '" ~ address ~ "', city = '" ~ city ~ "', telephone = '" ~ telephone ~ "']";
    }
}

/// Simple business object representing a pet.
class Pet : NamedEntity
{
    private LocalDate birthDate;
    private PetType type;
    private Owner owner;
    private Visit[] visits;

    /// A new pet. Its type and owner are null until set, as Java's are (FLINT-E0530 asks for the assignment).
    this()
    {
        type = null;
        owner = null;
    }

    ///
    LocalDate getBirthDate()
    {
        return birthDate;
    }

    ///
    void setBirthDate(LocalDate birthDate)
    {
        this.birthDate = birthDate;
    }

    ///
    PetType getType()
    {
        return type;
    }

    ///
    void setType(PetType type)
    {
        this.type = type;
    }

    ///
    Owner getOwner()
    {
        return owner;
    }

    ///
    void setOwner(Owner owner)
    {
        this.owner = owner;
    }

    /// The visits, newest first.
    List!Visit getVisits()
    {
        return sortedList(visits, (Visit a, Visit b) => a.getDate().compareTo(b.getDate()) > 0);
    }

    ///
    void setVisits(List!Visit visits)
    {
        this.visits = visits is null ? null : visits.toArray();
    }

    ///
    void addVisit(Visit visit)
    {
        visits ~= visit;
        visit.setPet(this);
    }
}

/// A pet type: cat, dog, ...
class PetType : NamedEntity
{
}

/// Simple JavaBean domain object representing a visit.
class Visit : BaseEntity
{
    private LocalDate date;
    private string description;
    private Pet pet;

    /// Creates a new instance of Visit for the current date.
    this()
    {
        date = LocalDate.now();
        pet = null;
    }

    ///
    LocalDate getDate()
    {
        return date;
    }

    ///
    void setDate(LocalDate date)
    {
        this.date = date;
    }

    ///
    string getDescription()
    {
        return description;
    }

    ///
    void setDescription(string description)
    {
        this.description = description;
    }

    ///
    Pet getPet()
    {
        return pet;
    }

    ///
    void setPet(Pet pet)
    {
        this.pet = pet;
    }
}

/// Simple JavaBean domain object representing a veterinarian.
class Vet : Person
{
    private Specialty[] specialties;

    /// The specialties, sorted by name, case-insensitively.
    List!Specialty getSpecialties()
    {
        return sortedList(specialties, (Specialty a, Specialty b) => compareIgnoreCase(a.getName(), b.getName()) < 0);
    }

    ///
    void setSpecialties(List!Specialty specialties)
    {
        this.specialties = specialties is null ? null : specialties.toArray();
    }

    /// The number of specialties.
    int getNrOfSpecialties()
    {
        return cast(int) specialties.length;
    }

    ///
    void addSpecialty(Specialty specialty)
    {
        specialties ~= specialty;
    }

    ///
    void clearSpecialties()
    {
        specialties = null;
    }
}

/// Models a `Vet`'s specialty (for example, dentistry).
class Specialty : NamedEntity
{
}

/// An application user, with roles.
class User
{
    private string username;
    private string password;
    private bool enabled;
    private Role[] roles;

    ///
    string getUsername()
    {
        return username;
    }

    ///
    void setUsername(string username)
    {
        this.username = username;
    }

    ///
    string getPassword()
    {
        return password;
    }

    ///
    void setPassword(string password)
    {
        this.password = password;
    }

    ///
    bool getEnabled()
    {
        return enabled;
    }

    ///
    void setEnabled(bool enabled)
    {
        this.enabled = enabled;
    }

    ///
    List!Role getRoles()
    {
        auto list = new ArrayList!Role;
        foreach (role; roles)
            list.add(role);
        return list;
    }

    ///
    void setRoles(List!Role roles)
    {
        this.roles = roles is null ? null : roles.toArray();
    }

    /// Add a role by name.
    void addRole(string roleName)
    {
        auto role = new Role;
        role.setName(roleName);
        roles ~= role;
    }
}

/// A user's role.
class Role : BaseEntity
{
    private User user;
    private string name;

    /// A new role. Its user is null until set, as Java's is (FLINT-E0530 asks for the assignment).
    this()
    {
        user = null;
    }

    ///
    User getUser()
    {
        return user;
    }

    ///
    void setUser(User user)
    {
        this.user = user;
    }

    ///
    string getName()
    {
        return name;
    }

    ///
    void setName(string name)
    {
        this.name = name;
    }
}

/// A sorted, read-only copy of `items` as a `List` (Java's `Collections.unmodifiableList` of a sorted copy).
private List!T sortedList(T)(T[] items, bool delegate(T, T) @safe less)
{
    // Java's List.sort is stable. An insertion sort is, too: a few pets, visits or specialties per entity, and no
    // std.algorithm sort instantiated per element type (petclinic's compile profile, size-levers).
    auto copy = items.dup;
    foreach (i; 1 .. copy.length)
    {
        auto item = copy[i];
        size_t j = i;
        for (; j > 0 && less(item, copy[j - 1]); --j)
            copy[j] = copy[j - 1];
        copy[j] = item;
    }
    auto list = new ArrayList!T;
    foreach (item; copy)
        list.add(item);
    return list;
}

/// Java's `String.CASE_INSENSITIVE_ORDER`.
private int compareIgnoreCase(string a, string b) pure nothrow @nogc
{
    import std.ascii : toLower;

    foreach (i; 0 .. a.length < b.length ? a.length : b.length)
    {
        const x = toLower(a[i]), y = toLower(b[i]);
        if (x != y)
            return x < y ? -1 : 1;
    }
    return a.length < b.length ? -1 : a.length > b.length ? 1 : 0;
}
