/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba): `org.springframework.samples.petclinic.repository`, the
repository interfaces, ported to Flint. Copyright 2002-2013 the original author or authors. Licensed under the Apache
License, Version 2.0. Modified by the Flint authors: Java → D syntax (R1); `Collection`, `List` and `Set` are
`flint.java.util`'s (R10).
+/
module org.springframework.samples.petclinic.repository;

import flint.data.domain : Page, Pageable;
import flint.java.util : Collection, List, Set;
import org.springframework.samples.petclinic.model;

@safe:

/// Repository class for `Owner` domain objects.
interface OwnerRepository
{
    /// Retrieve `Owner`s from the data store by last name, returning all owners whose last name starts with the
    /// given name.
    Collection!Owner findByLastName(string lastName);

    /// ditto, a page at a time.
    Page!Owner findByLastName(string lastName, Pageable pageable);

    /// Retrieve an `Owner` from the data store by id.
    Owner findById(int id);

    /// Save an `Owner` to the data store, either inserting or updating it.
    void save(Owner owner);

    /// Retrieve all `Owner`s from the data store.
    Collection!Owner findAll();

    /// ditto, a page at a time.
    Page!Owner findAll(Pageable pageable);

    /// Delete an `Owner` from the data store.
    void delete_(Owner owner);
}

/// Repository class for `Pet` domain objects.
interface PetRepository
{
    /// Retrieve all `PetType`s from the data store.
    List!PetType findPetTypes();

    /// Retrieve a `Pet` from the data store by id.
    Pet findById(int id);

    /// Save a `Pet` to the data store, either inserting or updating it.
    void save(Pet pet);

    /// Retrieve all `Pet`s from the data store.
    Collection!Pet findAll();

    /// ditto, a page at a time.
    Page!Pet findAll(Pageable pageable);

    /// Delete a `Pet` from the data store.
    void delete_(Pet pet);
}

/// Repository class for `PetType` domain objects.
interface PetTypeRepository
{
    /// Retrieve a `PetType` by id.
    PetType findById(int id);

    /// Retrieve a `PetType` by name.
    PetType findByName(string name);

    /// Retrieve all `PetType`s.
    Collection!PetType findAll();

    /// Save a `PetType`, either inserting or updating it.
    void save(PetType petType);

    /// Delete a `PetType`, with its pets and their visits.
    void delete_(PetType petType);
}

/// Repository class for `Specialty` domain objects.
interface SpecialtyRepository
{
    /// Retrieve a `Specialty` by id.
    Specialty findById(int id);

    /// Retrieve the `Specialty`s with the given names.
    List!Specialty findSpecialtiesByNameIn(Set!string names);

    /// Retrieve all `Specialty`s.
    Collection!Specialty findAll();

    /// Save a `Specialty`, either inserting or updating it.
    void save(Specialty specialty);

    /// Delete a `Specialty`.
    void delete_(Specialty specialty);
}

/// Repository class for `User` domain objects.
interface UserRepository
{
    /// Save a `User`, either inserting or updating it, with its roles.
    void save(User user);
}

/// Repository class for `Vet` domain objects.
interface VetRepository
{
    /// Retrieve all `Vet`s from the data store.
    Collection!Vet findAll();

    /// Retrieve a `Vet` by id.
    Vet findById(int id);

    /// Save a `Vet`, either inserting or updating it, with its specialties.
    void save(Vet vet);

    /// Delete a `Vet`.
    void delete_(Vet vet);
}

/// Repository class for `Visit` domain objects.
interface VisitRepository
{
    /// Save a `Visit` to the data store, either inserting or updating it.
    void save(Visit visit);

    /// Retrieve the `Visit`s of the pet with the given id.
    List!Visit findByPetId(int petId);

    /// Retrieve a `Visit` by id.
    Visit findById(int id);

    /// Retrieve all `Visit`s.
    Collection!Visit findAll();

    /// Delete a `Visit`.
    void delete_(Visit visit);
}
