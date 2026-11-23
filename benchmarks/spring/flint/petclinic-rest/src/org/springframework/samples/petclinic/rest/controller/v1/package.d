/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba): `org.springframework.samples.petclinic.rest.controller.v1`,
ported to Flint. Copyright 2016-2025 the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors:
- Java → D syntax, one module per Java package (R1).
- `RootRestControllerV1` reads the context path from the request, since Flint has no SpEL `servletContext`
  (`@Value("#{servletContext.contextPath}")`).
- `ResponseEntity<T>` is Flint's `ResponseEntity` (`ResponseEntity.of(body, status)` for `new ResponseEntity<>(body,
  status)`); `buildAndExpand` takes the id as text.
- The `@PreAuthorize` annotations are not written yet: they wait on flint-security (framework-core's port). The
  application runs with `petclinic.security.enable=false`, where Spring does not enforce them either.
+/
module org.springframework.samples.petclinic.rest.controller.v1;

import flint.http : HttpHeaders, HttpStatus, ResponseEntity;
import flint.jakarta.servlet.http : HttpServletRequest, HttpServletResponse;
import flint.java.util : ArrayList, LinkedHashSet, List, Set;
import flint.transaction.annotation : Transactional;
import flint.web.bind.annotation : CrossOrigin, RequestMapping, RestController;
import flint.web.util : UriComponentsBuilder;
import org.springframework.samples.petclinic.mapper : OwnerMapper, PetMapper, PetTypeMapper,
    SpecialtyMapper, UserMapper, VetMapper, VisitMapper;
import org.springframework.samples.petclinic.model : Owner, Pet, PetType, Specialty, User, Vet, Visit;
import org.springframework.samples.petclinic.rest.api : OwnersApi, PetsApi, PettypesApi,
    SpecialtiesApi, UsersApi, VetsApi, VisitsApi;
import org.springframework.samples.petclinic.rest.dto : OwnerDto, OwnerFieldsDto, PetDto, PetFieldsDto,
    PetTypeDto, PetTypeFieldsDto, SpecialtyDto, UserDto, VetDto, VisitDto, VisitFieldsDto;
import org.springframework.samples.petclinic.service : ClinicService, UserService;

@safe:

/// `headers.setLocation(UriComponentsBuilder.newInstance().path(path).buildAndExpand(id).toUri())`.
private HttpHeaders locationOf(string path, int id)
{
    import flint.engine.aot.text : decimal;

    HttpHeaders headers;
    headers.setLocation(UriComponentsBuilder.newInstance().path(path).buildAndExpand(decimal(long(id))).toUri());
    return headers;
}

/// `OwnerRestControllerV1`.
@RestController @CrossOrigin(exposedHeaders : ["errors, content-type"]) @RequestMapping("/api")
class OwnerRestControllerV1 : OwnersApi
{
    private ClinicService clinicService;
    private OwnerMapper ownerMapper;
    private PetMapper petMapper;
    private VisitMapper visitMapper;

    ///
    this(ClinicService clinicService, OwnerMapper ownerMapper, PetMapper petMapper, VisitMapper visitMapper)
    {
        this.clinicService = clinicService;
        this.ownerMapper = ownerMapper;
        this.petMapper = petMapper;
        this.visitMapper = visitMapper;
    }

    override ResponseEntity listOwners(string lastName)
    {
        auto owners = lastName !is null ? this.clinicService.findOwnerByLastName(
                lastName) : this.clinicService.findAllOwners();
        if (owners.isEmpty())
            return ResponseEntity(HttpStatus.NOT_FOUND);
        return ResponseEntity.of(ownerMapper.toOwnerDtoCollection(owners), HttpStatus.OK);
    }

    override ResponseEntity getOwner(int ownerId)
    {
        Owner owner = this.clinicService.findOwnerById(ownerId);
        if (owner is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        return ResponseEntity.of(ownerMapper.toOwnerDto(owner), HttpStatus.OK);
    }

    override ResponseEntity addOwner(OwnerFieldsDto ownerFieldsDto)
    {
        Owner owner = ownerMapper.toOwner(ownerFieldsDto);
        this.clinicService.saveOwner(owner);
        OwnerDto ownerDto = ownerMapper.toOwnerDto(owner);
        return ResponseEntity.of(ownerDto, locationOf("/api/owners/{id}", owner.getId()), HttpStatus.CREATED);
    }

    override ResponseEntity updateOwner(int ownerId, OwnerFieldsDto ownerFieldsDto)
    {
        Owner currentOwner = this.clinicService.findOwnerById(ownerId);
        if (currentOwner is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        currentOwner.setAddress(ownerFieldsDto.getAddress());
        currentOwner.setCity(ownerFieldsDto.getCity());
        currentOwner.setFirstName(ownerFieldsDto.getFirstName());
        currentOwner.setLastName(ownerFieldsDto.getLastName());
        currentOwner.setTelephone(ownerFieldsDto.getTelephone());
        this.clinicService.saveOwner(currentOwner);
        return ResponseEntity.of(ownerMapper.toOwnerDto(currentOwner), HttpStatus.NO_CONTENT);
    }

    @Transactional override ResponseEntity deleteOwner(int ownerId)
    {
        Owner owner = this.clinicService.findOwnerById(ownerId);
        if (owner is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        this.clinicService.deleteOwner(owner);
        return ResponseEntity(HttpStatus.NO_CONTENT);
    }

    override ResponseEntity addPetToOwner(int ownerId, PetFieldsDto petFieldsDto)
    {
        Owner owner = this.clinicService.findOwnerById(ownerId);
        if (owner is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        Pet pet = petMapper.toPet(petFieldsDto);
        owner.setId(ownerId);
        pet.setOwner(owner);
        pet.getType().setName(null);
        this.clinicService.savePet(pet);
        PetDto petDto = petMapper.toPetDto(pet);
        return ResponseEntity.of(petDto, locationOf("/api/pets/{id}", pet.getId()), HttpStatus.CREATED);
    }

    override ResponseEntity updateOwnersPet(int ownerId, int petId, PetFieldsDto petFieldsDto)
    {
        const currentOwner = this.clinicService.findOwnerById(ownerId);
        if (currentOwner !is null)
        {
            Pet currentPet = this.clinicService.findPetById(petId);
            if (currentPet !is null)
            {
                currentPet.setBirthDate(petFieldsDto.getBirthDate());
                currentPet.setName(petFieldsDto.getName());
                currentPet.setType(petMapper.toPetType(petFieldsDto.getType()));
                this.clinicService.savePet(currentPet);
                return ResponseEntity(HttpStatus.NO_CONTENT);
            }
        }
        return ResponseEntity(HttpStatus.NOT_FOUND);
    }

    override ResponseEntity addVisitToOwner(int ownerId, int petId, VisitFieldsDto visitFieldsDto)
    {
        Visit visit = visitMapper.toVisit(visitFieldsDto);
        auto pet = new Pet();
        pet.setId(petId);
        visit.setPet(pet);
        this.clinicService.saveVisit(visit);
        VisitDto visitDto = visitMapper.toVisitDto(visit);
        return ResponseEntity.of(visitDto, locationOf("/api/visits/{id}", visit.getId()), HttpStatus.CREATED);
    }

    override ResponseEntity getOwnersPet(int ownerId, int petId)
    {
        Owner owner = this.clinicService.findOwnerById(ownerId);
        if (owner !is null)
        {
            Pet pet = owner.getPet(petId);
            if (pet !is null)
                return ResponseEntity.of(petMapper.toPetDto(pet), HttpStatus.OK);
        }
        return ResponseEntity(HttpStatus.NOT_FOUND);
    }
}

/// `PetRestControllerV1`.
@RestController @CrossOrigin(exposedHeaders : ["errors, content-type"]) @RequestMapping("api")
class PetRestControllerV1 : PetsApi
{
    private ClinicService clinicService;
    private PetMapper petMapper;

    ///
    this(ClinicService clinicService, PetMapper petMapper)
    {
        this.clinicService = clinicService;
        this.petMapper = petMapper;
    }

    override ResponseEntity getPet(int petId)
    {
        PetDto pet = petMapper.toPetDto(this.clinicService.findPetById(petId));
        if (pet is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        return ResponseEntity.of(pet, HttpStatus.OK);
    }

    override ResponseEntity listPets()
    {
        auto pets = new ArrayList!PetDto(petMapper.toPetsDto(this.clinicService.findAllPets()));
        if (pets.isEmpty())
            return ResponseEntity(HttpStatus.NOT_FOUND);
        return ResponseEntity.of(cast(List!PetDto) pets, HttpStatus.OK);
    }

    override ResponseEntity updatePet(int petId, PetDto petDto)
    {
        Pet currentPet = this.clinicService.findPetById(petId);
        if (currentPet is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        currentPet.setBirthDate(petDto.getBirthDate());
        currentPet.setName(petDto.getName());
        currentPet.setType(petMapper.toPetType(petDto.getType()));
        this.clinicService.savePet(currentPet);
        return ResponseEntity.of(petMapper.toPetDto(currentPet), HttpStatus.NO_CONTENT);
    }

    override ResponseEntity deletePet(int petId)
    {
        Pet pet = this.clinicService.findPetById(petId);
        if (pet is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        this.clinicService.deletePet(pet);
        return ResponseEntity(HttpStatus.NO_CONTENT);
    }
}

/// `VisitRestControllerV1`.
@RestController @CrossOrigin(exposedHeaders : ["errors, content-type"]) @RequestMapping("api")
class VisitRestControllerV1 : VisitsApi
{
    private ClinicService clinicService;
    private VisitMapper visitMapper;

    ///
    this(ClinicService clinicService, VisitMapper visitMapper)
    {
        this.clinicService = clinicService;
        this.visitMapper = visitMapper;
    }

    override ResponseEntity listVisits()
    {
        auto visits = new ArrayList!Visit(this.clinicService.findAllVisits());
        if (visits.isEmpty())
            return ResponseEntity(HttpStatus.NOT_FOUND);
        return ResponseEntity.of(cast(List!VisitDto) new ArrayList!VisitDto(visitMapper.toVisitsDto(visits)),
                HttpStatus.OK);
    }

    override ResponseEntity getVisit(int visitId)
    {
        Visit visit = this.clinicService.findVisitById(visitId);
        if (visit is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        return ResponseEntity.of(visitMapper.toVisitDto(visit), HttpStatus.OK);
    }

    override ResponseEntity addVisit(VisitDto visitDto)
    {
        Visit visit = visitMapper.toVisit(visitDto);
        this.clinicService.saveVisit(visit);
        visitDto = visitMapper.toVisitDto(visit);
        return ResponseEntity.of(visitDto, locationOf("/api/visits/{id}", visit.getId()), HttpStatus.CREATED);
    }

    override ResponseEntity updateVisit(int visitId, VisitFieldsDto visitDto)
    {
        Visit currentVisit = this.clinicService.findVisitById(visitId);
        if (currentVisit is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        currentVisit.setDate(visitDto.getDate());
        currentVisit.setDescription(visitDto.getDescription());
        this.clinicService.saveVisit(currentVisit);
        return ResponseEntity.of(visitMapper.toVisitDto(currentVisit), HttpStatus.NO_CONTENT);
    }

    @Transactional override ResponseEntity deleteVisit(int visitId)
    {
        Visit visit = this.clinicService.findVisitById(visitId);
        if (visit is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        this.clinicService.deleteVisit(visit);
        return ResponseEntity(HttpStatus.NO_CONTENT);
    }
}

/// `PetTypeRestControllerV1`.
@RestController @CrossOrigin(exposedHeaders : ["errors, content-type"]) @RequestMapping("api")
class PetTypeRestControllerV1 : PettypesApi
{
    private ClinicService clinicService;
    private PetTypeMapper petTypeMapper;

    ///
    this(ClinicService clinicService, PetTypeMapper petTypeMapper)
    {
        this.clinicService = clinicService;
        this.petTypeMapper = petTypeMapper;
    }

    override ResponseEntity listPetTypes()
    {
        auto petTypes = new ArrayList!PetType(this.clinicService.findAllPetTypes());
        if (petTypes.isEmpty())
            return ResponseEntity(HttpStatus.NOT_FOUND);
        return ResponseEntity.of(petTypeMapper.toPetTypeDtos(petTypes), HttpStatus.OK);
    }

    override ResponseEntity getPetType(int petTypeId)
    {
        PetType petType = this.clinicService.findPetTypeById(petTypeId);
        if (petType is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        return ResponseEntity.of(petTypeMapper.toPetTypeDto(petType), HttpStatus.OK);
    }

    override ResponseEntity addPetType(PetTypeFieldsDto petTypeFieldsDto)
    {
        PetType type = petTypeMapper.toPetType(petTypeFieldsDto);
        this.clinicService.savePetType(type);
        return ResponseEntity.of(petTypeMapper.toPetTypeDto(type), locationOf("/api/pettypes/{id}",
                type.getId()), HttpStatus.CREATED);
    }

    override ResponseEntity updatePetType(int petTypeId, PetTypeDto petTypeDto)
    {
        PetType currentPetType = this.clinicService.findPetTypeById(petTypeId);
        if (currentPetType is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        currentPetType.setName(petTypeDto.getName());
        this.clinicService.savePetType(currentPetType);
        return ResponseEntity.of(petTypeMapper.toPetTypeDto(currentPetType), HttpStatus.NO_CONTENT);
    }

    @Transactional override ResponseEntity deletePetType(int petTypeId)
    {
        PetType petType = this.clinicService.findPetTypeById(petTypeId);
        if (petType is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        this.clinicService.deletePetType(petType);
        return ResponseEntity(HttpStatus.NO_CONTENT);
    }
}

/// `SpecialtyRestControllerV1`.
@RestController @CrossOrigin(exposedHeaders : ["errors, content-type"]) @RequestMapping("api")
class SpecialtyRestControllerV1 : SpecialtiesApi
{
    private ClinicService clinicService;
    private SpecialtyMapper specialtyMapper;

    ///
    this(ClinicService clinicService, SpecialtyMapper specialtyMapper)
    {
        this.clinicService = clinicService;
        this.specialtyMapper = specialtyMapper;
    }

    override ResponseEntity listSpecialties()
    {
        auto specialties = new ArrayList!SpecialtyDto();
        specialties.addAll(specialtyMapper.toSpecialtyDtos(this.clinicService.findAllSpecialties()));
        if (specialties.isEmpty())
            return ResponseEntity(HttpStatus.NOT_FOUND);
        return ResponseEntity.of(cast(List!SpecialtyDto) specialties, HttpStatus.OK);
    }

    override ResponseEntity getSpecialty(int specialtyId)
    {
        Specialty specialty = this.clinicService.findSpecialtyById(specialtyId);
        if (specialty is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        return ResponseEntity.of(specialtyMapper.toSpecialtyDto(specialty), HttpStatus.OK);
    }

    override ResponseEntity addSpecialty(SpecialtyDto specialtyDto)
    {
        Specialty specialty = specialtyMapper.toSpecialty(specialtyDto);
        this.clinicService.saveSpecialty(specialty);
        return ResponseEntity.of(specialtyMapper.toSpecialtyDto(specialty),
                locationOf("/api/specialties/{id}", specialty.getId()), HttpStatus.CREATED);
    }

    override ResponseEntity updateSpecialty(int specialtyId, SpecialtyDto specialtyDto)
    {
        Specialty currentSpecialty = this.clinicService.findSpecialtyById(specialtyId);
        if (currentSpecialty is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        currentSpecialty.setName(specialtyDto.getName());
        this.clinicService.saveSpecialty(currentSpecialty);
        return ResponseEntity.of(specialtyMapper.toSpecialtyDto(currentSpecialty), HttpStatus.NO_CONTENT);
    }

    @Transactional override ResponseEntity deleteSpecialty(int specialtyId)
    {
        Specialty specialty = this.clinicService.findSpecialtyById(specialtyId);
        if (specialty is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        this.clinicService.deleteSpecialty(specialty);
        return ResponseEntity(HttpStatus.NO_CONTENT);
    }
}

/// `VetRestControllerV1`.
@RestController @CrossOrigin(exposedHeaders : ["errors, content-type"]) @RequestMapping("api")
class VetRestControllerV1 : VetsApi
{
    private ClinicService clinicService;
    private VetMapper vetMapper;
    private SpecialtyMapper specialtyMapper;

    ///
    this(ClinicService clinicService, VetMapper vetMapper, SpecialtyMapper specialtyMapper)
    {
        this.clinicService = clinicService;
        this.vetMapper = vetMapper;
        this.specialtyMapper = specialtyMapper;
    }

    override ResponseEntity listVets()
    {
        auto vets = new ArrayList!VetDto(vetMapper.toVetDtos(this.clinicService.findAllVets()));
        if (vets.isEmpty())
            return ResponseEntity(HttpStatus.NOT_FOUND);
        return ResponseEntity.of(cast(List!VetDto) vets, HttpStatus.OK);
    }

    override ResponseEntity getVet(int vetId)
    {
        Vet vet = this.clinicService.findVetById(vetId);
        if (vet is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        return ResponseEntity.of(vetMapper.toVetDto(vet), HttpStatus.OK);
    }

    override ResponseEntity addVet(VetDto vetDto)
    {
        Vet vet = vetMapper.toVet(vetDto);
        if (vet.getNrOfSpecialties() > 0)
            vet.setSpecialties(this.clinicService.findSpecialtiesByNameIn(namesOf(vet)));
        this.clinicService.saveVet(vet);
        return ResponseEntity.of(vetMapper.toVetDto(vet), locationOf("/api/vets/{id}",
                vet.getId()), HttpStatus.CREATED);
    }

    override ResponseEntity updateVet(int vetId, VetDto vetDto)
    {
        Vet currentVet = this.clinicService.findVetById(vetId);
        if (currentVet is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        currentVet.setFirstName(vetDto.getFirstName());
        currentVet.setLastName(vetDto.getLastName());
        currentVet.clearSpecialties();
        foreach (spec; specialtyMapper.toSpecialtys(vetDto.getSpecialties()))
            currentVet.addSpecialty(spec);
        if (currentVet.getNrOfSpecialties() > 0)
            currentVet.setSpecialties(this.clinicService.findSpecialtiesByNameIn(namesOf(currentVet)));
        this.clinicService.saveVet(currentVet);
        return ResponseEntity.of(vetMapper.toVetDto(currentVet), HttpStatus.NO_CONTENT);
    }

    @Transactional override ResponseEntity deleteVet(int vetId)
    {
        Vet vet = this.clinicService.findVetById(vetId);
        if (vet is null)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        this.clinicService.deleteVet(vet);
        return ResponseEntity(HttpStatus.NO_CONTENT);
    }

    // `vet.getSpecialties().stream().map(Specialty::getName).collect(Collectors.toSet())`.
    private static Set!string namesOf(Vet vet)
    {
        auto names = new LinkedHashSet!string();
        foreach (specialty; vet.getSpecialties())
            names.add(specialty.getName());
        return names;
    }
}

/// `UserRestControllerV1`.
@RestController @CrossOrigin(exposedHeaders : ["errors, content-type"]) @RequestMapping("api")
class UserRestControllerV1 : UsersApi
{
    private UserService userService;
    private UserMapper userMapper;

    ///
    this(UserService userService, UserMapper userMapper)
    {
        this.userService = userService;
        this.userMapper = userMapper;
    }

    override ResponseEntity addUser(UserDto userDto)
    {
        User user = userMapper.toUser(userDto);
        this.userService.saveUser(user);
        return ResponseEntity.of(userMapper.toUserDto(user), HttpHeaders.init, HttpStatus.CREATED);
    }
}

/// `RootRestControllerV1`: the root redirects to the Swagger UI.
@RestController @CrossOrigin(exposedHeaders : ["errors, content-type"]) @RequestMapping("/")
class RootRestControllerV1
{
    /// `response.sendRedirect(servletContextPath + "/swagger-ui/index.html")`.
    @RequestMapping(value : ["/"]) void redirectToSwagger(HttpServletRequest request, HttpServletResponse response)
    {
        response.sendRedirect(request.getContextPath() ~ "/swagger-ui/index.html");
    }
}
