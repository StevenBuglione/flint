/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba): `org.springframework.samples.petclinic.service`, ported to
Flint. Copyright 2002-2013 the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: Java → D syntax (R1); `Supplier<T>` is a delegate (R9); `UserServiceImpl` takes its
repository through its constructor instead of a field `@Autowired`, which is the same injection.
+/
module org.springframework.samples.petclinic.service;

import flint.dao : EmptyResultDataAccessException;
import flint.data.domain : Page, Pageable;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : Collection, List, Set;
import flint.orm : ObjectRetrievalFailureException;
import flint.stereotype : Service;
import flint.transaction.annotation : Transactional;
import org.springframework.samples.petclinic.model;
import org.springframework.samples.petclinic.repository;

@safe:

/// Mostly used as a facade so all controllers have a single point of entry.
interface ClinicService
{
    ///
    Pet findPetById(int id);
    ///
    Collection!Pet findAllPets();
    ///
    Page!Pet findPets(Pageable pageable);
    ///
    void savePet(Pet pet);
    ///
    void deletePet(Pet pet);
    ///
    Collection!Visit findVisitsByPetId(int petId);
    ///
    Visit findVisitById(int visitId);
    ///
    Collection!Visit findAllVisits();
    ///
    void saveVisit(Visit visit);
    ///
    void deleteVisit(Visit visit);
    ///
    Vet findVetById(int id);
    ///
    Collection!Vet findVets();
    ///
    Collection!Vet findAllVets();
    ///
    void saveVet(Vet vet);
    ///
    void deleteVet(Vet vet);
    ///
    Owner findOwnerById(int id);
    ///
    Collection!Owner findAllOwners();
    ///
    Page!Owner findOwners(string lastName, Pageable pageable);
    ///
    void saveOwner(Owner owner);
    ///
    void deleteOwner(Owner owner);
    ///
    Collection!Owner findOwnerByLastName(string lastName);
    ///
    PetType findPetTypeById(int petTypeId);
    ///
    Collection!PetType findAllPetTypes();
    ///
    Collection!PetType findPetTypes();
    ///
    void savePetType(PetType petType);
    ///
    void deletePetType(PetType petType);
    ///
    Specialty findSpecialtyById(int specialtyId);
    ///
    Collection!Specialty findAllSpecialties();
    ///
    void saveSpecialty(Specialty specialty);
    ///
    void deleteSpecialty(Specialty specialty);
    ///
    List!Specialty findSpecialtiesByNameIn(Set!string names);
}

/// Mostly used as a facade for all Petclinic controllers. Also a placeholder for `@Transactional` and `@Cacheable`
/// annotations.
@Service class ClinicServiceImpl : ClinicService
{
    private PetRepository petRepository;
    private VetRepository vetRepository;
    private OwnerRepository ownerRepository;
    private VisitRepository visitRepository;
    private SpecialtyRepository specialtyRepository;
    private PetTypeRepository petTypeRepository;

    ///
    this(PetRepository petRepository, VetRepository vetRepository, OwnerRepository ownerRepository,
            VisitRepository visitRepository, SpecialtyRepository specialtyRepository,
            PetTypeRepository petTypeRepository)
    {
        this.petRepository = petRepository;
        this.vetRepository = vetRepository;
        this.ownerRepository = ownerRepository;
        this.visitRepository = visitRepository;
        this.specialtyRepository = specialtyRepository;
        this.petTypeRepository = petTypeRepository;
    }

    @Transactional(readOnly : true) override Collection!Pet findAllPets()
    {
        return petRepository.findAll();
    }

    @Transactional(readOnly : true) override Page!Pet findPets(Pageable pageable)
    {
        return petRepository.findAll(pageable);
    }

    @Transactional override void deletePet(Pet pet)
    {
        petRepository.delete_(pet);
    }

    @Transactional(readOnly : true) override Visit findVisitById(int visitId)
    {
        return findEntityById(() => visitRepository.findById(visitId));
    }

    @Transactional(readOnly : true) override Collection!Visit findAllVisits()
    {
        return visitRepository.findAll();
    }

    @Transactional override void deleteVisit(Visit visit)
    {
        visitRepository.delete_(visit);
    }

    @Transactional(readOnly : true) override Vet findVetById(int id)
    {
        return findEntityById(() => vetRepository.findById(id));
    }

    @Transactional(readOnly : true) override Collection!Vet findAllVets()
    {
        return vetRepository.findAll();
    }

    @Transactional override void saveVet(Vet vet)
    {
        vetRepository.save(vet);
    }

    @Transactional override void deleteVet(Vet vet)
    {
        vetRepository.delete_(vet);
    }

    @Transactional(readOnly : true) override Collection!Owner findAllOwners()
    {
        return ownerRepository.findAll();
    }

    @Transactional(readOnly : true) override Page!Owner findOwners(string lastName, Pageable pageable)
    {
        if (lastName !is null)
            return ownerRepository.findByLastName(lastName, pageable);
        return ownerRepository.findAll(pageable);
    }

    @Transactional override void deleteOwner(Owner owner)
    {
        ownerRepository.delete_(owner);
    }

    @Transactional(readOnly : true) override PetType findPetTypeById(int petTypeId)
    {
        return findEntityById(() => petTypeRepository.findById(petTypeId));
    }

    @Transactional(readOnly : true) override Collection!PetType findAllPetTypes()
    {
        return petTypeRepository.findAll();
    }

    @Transactional override void savePetType(PetType petType)
    {
        petTypeRepository.save(petType);
    }

    @Transactional override void deletePetType(PetType petType)
    {
        petTypeRepository.delete_(petType);
    }

    @Transactional(readOnly : true) override Specialty findSpecialtyById(int specialtyId)
    {
        return findEntityById(() => specialtyRepository.findById(specialtyId));
    }

    @Transactional(readOnly : true) override Collection!Specialty findAllSpecialties()
    {
        return specialtyRepository.findAll();
    }

    @Transactional override void saveSpecialty(Specialty specialty)
    {
        specialtyRepository.save(specialty);
    }

    @Transactional override void deleteSpecialty(Specialty specialty)
    {
        specialtyRepository.delete_(specialty);
    }

    @Transactional(readOnly : true) override Collection!PetType findPetTypes()
    {
        return petRepository.findPetTypes();
    }

    @Transactional(readOnly : true) override Owner findOwnerById(int id)
    {
        return findEntityById(() => ownerRepository.findById(id));
    }

    @Transactional(readOnly : true) override Pet findPetById(int id)
    {
        return findEntityById(() => petRepository.findById(id));
    }

    @Transactional override void savePet(Pet pet)
    {
        pet.setType(findPetTypeById(pet.getType().getId()));
        petRepository.save(pet);
    }

    @Transactional override void saveVisit(Visit visit)
    {
        visitRepository.save(visit);
    }

    @Transactional(readOnly : true) override Collection!Vet findVets()
    {
        return vetRepository.findAll();
    }

    @Transactional override void saveOwner(Owner owner)
    {
        ownerRepository.save(owner);
    }

    @Transactional(readOnly : true) override Collection!Owner findOwnerByLastName(string lastName)
    {
        return ownerRepository.findByLastName(lastName);
    }

    @Transactional(readOnly : true) override Collection!Visit findVisitsByPetId(int petId)
    {
        return visitRepository.findByPetId(petId);
    }

    @Transactional(readOnly : true) override List!Specialty findSpecialtiesByNameIn(Set!string names)
    {
        return findEntityById(() => specialtyRepository.findSpecialtiesByNameIn(names));
    }

    /// The supplier's entity, or null when it was not found.
    private T findEntityById(T)(scope T delegate() @safe supplier)
    {
        try
            return supplier();
        catch (ObjectRetrievalFailureException e)
            return null;
        catch (EmptyResultDataAccessException e)
            return null;
    }
}

/// The users of the application.
interface UserService
{
    /// Save a user with its roles.
    void saveUser(User user);
}

/// Saves users, prefixing their role names with `ROLE_`.
@Service class UserServiceImpl : UserService
{
    private UserRepository userRepository;

    ///
    this(UserRepository userRepository)
    {
        this.userRepository = userRepository;
    }

    @Transactional override void saveUser(User user)
    {
        if (user.getRoles() is null || user.getRoles().isEmpty())
            throw new IllegalArgumentException("User must have at least a role set!");
        foreach (role; user.getRoles().toArray())
        {
            if (role.getName().length < 5 || role.getName()[0 .. 5] != "ROLE_")
                role.setName("ROLE_" ~ role.getName());
            if (role.getUser() is null)
                role.setUser(user);
        }
        userRepository.save(user);
    }
}
