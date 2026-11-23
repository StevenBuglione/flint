/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba): `org.springframework.samples.petclinic.mapper`, the
MapStruct mapper interfaces, and the `*MapperImpl` classes MapStruct 1.6 generates for them at build time,
translated to D.
Copyright the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors:
- One module for the package (R1), with the generated implementations beside their interfaces, as MapStruct puts
  them in the same Java package. Flint has no annotation processor, so the generated code is written out.
- A default method is a `final` interface method (R3); `@Autowired` fields are constructor-injected.
- `User.roles` is a `List` here (see the model module), so `Set<Role>` is `List!Role`.
- A DTO's `Integer` is a `Nullable!int` and an entity's an `int` with 0 for new (see the model and dto modules):
  `boxedId` and `unboxedId` convert between them where MapStruct copies the `Integer`.
+/
module org.springframework.samples.petclinic.mapper;

import flint.data.domain : Page;
import flint.java.util : ArrayList, Collection, List;
import flint.stereotype : Component;
import std.typecons : Nullable;
import org.springframework.samples.petclinic.model : Owner, Pet, PetType, Role, Specialty, User, Vet, Visit;
import org.springframework.samples.petclinic.rest.dto : OwnerDto, OwnerFieldsDto, OwnerPageDto,
    PetDto, PetFieldsDto, PetPageDto, PetTypeDto, PetTypeFieldsDto, RoleDto, SpecialtyDto, UserDto,
    VetDto, VetFieldsDto, VisitDto, VisitFieldsDto;

@safe:

/// An entity id as a DTO's `Integer`: 0, a new entity's id, is null.
private Nullable!int boxedId(int id)
{
    return id == 0 ? Nullable!int.init : Nullable!int(id);
}

/// A DTO's `Integer` id as an entity id: null is 0, a new entity's id.
private int unboxedId(Nullable!int id)
{
    return id.isNull ? 0 : id.get;
}

/// `OwnerMapper`.
interface OwnerMapper
{
    ///
    OwnerDto toOwnerDto(Owner owner);

    ///
    Owner toOwner(OwnerDto ownerDto);

    ///
    Owner toOwner(OwnerFieldsDto ownerDto);

    ///
    List!OwnerDto toOwnerDtoCollection(Collection!Owner ownerCollection);

    ///
    Collection!Owner toOwners(Collection!OwnerDto ownerDtos);

    ///
    final OwnerPageDto toOwnerPageDto(Page!Owner ownerPage)
    {
        auto ownerPageDto = new OwnerPageDto();
        ownerPageDto.setContent(toOwnerDtoCollection(ownerPage.getContent()));
        ownerPageDto.setPage(Nullable!int(ownerPage.getNumber()));
        ownerPageDto.setSize(Nullable!int(ownerPage.getSize()));
        ownerPageDto.setTotalElements(ownerPage.getTotalElements());
        ownerPageDto.setTotalPages(Nullable!int(ownerPage.getTotalPages()));
        return ownerPageDto;
    }
}

/// `OwnerMapperImpl`: the implementation MapStruct generates for `OwnerMapper`.
@Component class OwnerMapperImpl : OwnerMapper
{
    private PetMapper petMapper;

    ///
    this(PetMapper petMapper)
    {
        this.petMapper = petMapper;
    }

    override OwnerDto toOwnerDto(Owner owner)
    {
        if (owner is null)
        {
            return null;
        }
        auto ownerDto = new OwnerDto();
        ownerDto.setFirstName(owner.getFirstName());
        ownerDto.setLastName(owner.getLastName());
        ownerDto.setAddress(owner.getAddress());
        ownerDto.setCity(owner.getCity());
        ownerDto.setTelephone(owner.getTelephone());
        ownerDto.setId(boxedId(owner.getId()));
        ownerDto.setPets(petListToPetDtoList(owner.getPets()));
        return ownerDto;
    }

    override Owner toOwner(OwnerDto ownerDto)
    {
        if (ownerDto is null)
        {
            return null;
        }
        auto owner = new Owner();
        owner.setId(unboxedId(ownerDto.getId()));
        owner.setFirstName(ownerDto.getFirstName());
        owner.setLastName(ownerDto.getLastName());
        owner.setAddress(ownerDto.getAddress());
        owner.setCity(ownerDto.getCity());
        owner.setTelephone(ownerDto.getTelephone());
        owner.setPets(petDtoListToPetList(ownerDto.getPets()));
        return owner;
    }

    override Owner toOwner(OwnerFieldsDto ownerDto)
    {
        if (ownerDto is null)
        {
            return null;
        }
        auto owner = new Owner();
        owner.setFirstName(ownerDto.getFirstName());
        owner.setLastName(ownerDto.getLastName());
        owner.setAddress(ownerDto.getAddress());
        owner.setCity(ownerDto.getCity());
        owner.setTelephone(ownerDto.getTelephone());
        return owner;
    }

    override List!OwnerDto toOwnerDtoCollection(Collection!Owner ownerCollection)
    {
        if (ownerCollection is null)
        {
            return null;
        }
        List!OwnerDto list = new ArrayList!OwnerDto();
        foreach (owner; ownerCollection)
        {
            list.add(toOwnerDto(owner));
        }
        return list;
    }

    override Collection!Owner toOwners(Collection!OwnerDto ownerDtos)
    {
        if (ownerDtos is null)
        {
            return null;
        }
        Collection!Owner collection = new ArrayList!Owner();
        foreach (ownerDto; ownerDtos)
        {
            collection.add(toOwner(ownerDto));
        }
        return collection;
    }

    protected List!PetDto petListToPetDtoList(List!Pet list)
    {
        if (list is null)
        {
            return null;
        }
        List!PetDto list1 = new ArrayList!PetDto();
        foreach (pet; list)
        {
            list1.add(petMapper.toPetDto(pet));
        }
        return list1;
    }

    protected List!Pet petDtoListToPetList(List!PetDto list)
    {
        if (list is null)
        {
            return null;
        }
        List!Pet list1 = new ArrayList!Pet();
        foreach (petDto; list)
        {
            list1.add(petMapper.toPet(petDto));
        }
        return list1;
    }
}

/// `PetMapper`.
interface PetMapper
{
    ///
    PetDto toPetDto(Pet pet);

    ///
    Collection!PetDto toPetsDto(Collection!Pet pets);

    ///
    Collection!Pet toPets(Collection!PetDto pets);

    ///
    Pet toPet(PetDto petDto);

    ///
    Pet toPet(PetFieldsDto petFieldsDto);

    ///
    PetTypeDto toPetTypeDto(PetType petType);

    ///
    PetType toPetType(PetTypeDto petTypeDto);

    ///
    Collection!PetTypeDto toPetTypeDtos(Collection!PetType petTypes);

    ///
    final PetPageDto toPetPageDto(Page!Pet petPage)
    {
        auto petPageDto = new PetPageDto();
        petPageDto.setContent(toPetsDto(petPage.getContent()).stream().toList());
        petPageDto.setPage(Nullable!int(petPage.getNumber()));
        petPageDto.setSize(Nullable!int(petPage.getSize()));
        petPageDto.setTotalElements(petPage.getTotalElements());
        petPageDto.setTotalPages(Nullable!int(petPage.getTotalPages()));
        return petPageDto;
    }
}

/// `PetMapperImpl`: the implementation MapStruct generates for `PetMapper`.
@Component class PetMapperImpl : PetMapper
{
    private VisitMapper visitMapper;

    ///
    this(VisitMapper visitMapper)
    {
        this.visitMapper = visitMapper;
    }

    override PetDto toPetDto(Pet pet)
    {
        if (pet is null)
        {
            return null;
        }
        auto petDto = new PetDto();
        petDto.setOwnerId(boxedId(petOwnerId(pet)));
        petDto.setName(pet.getName());
        petDto.setBirthDate(pet.getBirthDate());
        petDto.setType(toPetTypeDto(pet.getType()));
        petDto.setId(boxedId(pet.getId()));
        petDto.setVisits(visitListToVisitDtoList(pet.getVisits()));
        return petDto;
    }

    override Collection!PetDto toPetsDto(Collection!Pet pets)
    {
        if (pets is null)
        {
            return null;
        }
        Collection!PetDto collection = new ArrayList!PetDto();
        foreach (pet; pets)
        {
            collection.add(toPetDto(pet));
        }
        return collection;
    }

    override Collection!Pet toPets(Collection!PetDto pets)
    {
        if (pets is null)
        {
            return null;
        }
        Collection!Pet collection = new ArrayList!Pet();
        foreach (petDto; pets)
        {
            collection.add(toPet(petDto));
        }
        return collection;
    }

    override Pet toPet(PetDto petDto)
    {
        if (petDto is null)
        {
            return null;
        }
        auto pet = new Pet();
        pet.setOwner(petDtoToOwner(petDto));
        pet.setId(unboxedId(petDto.getId()));
        pet.setName(petDto.getName());
        pet.setBirthDate(petDto.getBirthDate());
        pet.setType(toPetType(petDto.getType()));
        pet.setVisits(visitDtoListToVisitList(petDto.getVisits()));
        return pet;
    }

    override Pet toPet(PetFieldsDto petFieldsDto)
    {
        if (petFieldsDto is null)
        {
            return null;
        }
        auto pet = new Pet();
        pet.setName(petFieldsDto.getName());
        pet.setBirthDate(petFieldsDto.getBirthDate());
        pet.setType(toPetType(petFieldsDto.getType()));
        return pet;
    }

    override PetTypeDto toPetTypeDto(PetType petType)
    {
        if (petType is null)
        {
            return null;
        }
        auto petTypeDto = new PetTypeDto();
        petTypeDto.setName(petType.getName());
        petTypeDto.setId(boxedId(petType.getId()));
        return petTypeDto;
    }

    override PetType toPetType(PetTypeDto petTypeDto)
    {
        if (petTypeDto is null)
        {
            return null;
        }
        auto petType = new PetType();
        petType.setId(unboxedId(petTypeDto.getId()));
        petType.setName(petTypeDto.getName());
        return petType;
    }

    override Collection!PetTypeDto toPetTypeDtos(Collection!PetType petTypes)
    {
        if (petTypes is null)
        {
            return null;
        }
        Collection!PetTypeDto collection = new ArrayList!PetTypeDto();
        foreach (petType; petTypes)
        {
            collection.add(toPetTypeDto(petType));
        }
        return collection;
    }

    private int petOwnerId(Pet pet)
    {
        auto owner = pet.getOwner();
        if (owner is null)
        {
            return 0;
        }
        return owner.getId();
    }

    protected List!VisitDto visitListToVisitDtoList(List!Visit list)
    {
        if (list is null)
        {
            return null;
        }
        List!VisitDto list1 = new ArrayList!VisitDto();
        foreach (visit; list)
        {
            list1.add(visitMapper.toVisitDto(visit));
        }
        return list1;
    }

    protected Owner petDtoToOwner(PetDto petDto)
    {
        if (petDto is null)
        {
            return null;
        }
        auto owner = new Owner();
        owner.setId(unboxedId(petDto.getOwnerId()));
        return owner;
    }

    protected List!Visit visitDtoListToVisitList(List!VisitDto list)
    {
        if (list is null)
        {
            return null;
        }
        List!Visit list1 = new ArrayList!Visit();
        foreach (visitDto; list)
        {
            list1.add(visitMapper.toVisit(visitDto));
        }
        return list1;
    }
}

/// `PetTypeMapper`.
interface PetTypeMapper
{
    ///
    PetType toPetType(PetTypeDto petTypeDto);

    ///
    PetType toPetType(PetTypeFieldsDto petTypeFieldsDto);

    ///
    PetTypeDto toPetTypeDto(PetType petType);

    ///
    PetTypeFieldsDto toPetTypeFieldsDto(PetType petType);

    ///
    List!PetTypeDto toPetTypeDtos(Collection!PetType petTypes);
}

/// `PetTypeMapperImpl`: the implementation MapStruct generates for `PetTypeMapper`.
@Component class PetTypeMapperImpl : PetTypeMapper
{

    override PetType toPetType(PetTypeDto petTypeDto)
    {
        if (petTypeDto is null)
        {
            return null;
        }
        auto petType = new PetType();
        petType.setId(unboxedId(petTypeDto.getId()));
        petType.setName(petTypeDto.getName());
        return petType;
    }

    override PetType toPetType(PetTypeFieldsDto petTypeFieldsDto)
    {
        if (petTypeFieldsDto is null)
        {
            return null;
        }
        auto petType = new PetType();
        petType.setName(petTypeFieldsDto.getName());
        return petType;
    }

    override PetTypeDto toPetTypeDto(PetType petType)
    {
        if (petType is null)
        {
            return null;
        }
        auto petTypeDto = new PetTypeDto();
        petTypeDto.setName(petType.getName());
        petTypeDto.setId(boxedId(petType.getId()));
        return petTypeDto;
    }

    override PetTypeFieldsDto toPetTypeFieldsDto(PetType petType)
    {
        if (petType is null)
        {
            return null;
        }
        auto petTypeFieldsDto = new PetTypeFieldsDto();
        petTypeFieldsDto.setName(petType.getName());
        return petTypeFieldsDto;
    }

    override List!PetTypeDto toPetTypeDtos(Collection!PetType petTypes)
    {
        if (petTypes is null)
        {
            return null;
        }
        List!PetTypeDto list = new ArrayList!PetTypeDto();
        foreach (petType; petTypes)
        {
            list.add(toPetTypeDto(petType));
        }
        return list;
    }
}

/// `SpecialtyMapper`.
interface SpecialtyMapper
{
    ///
    Specialty toSpecialty(SpecialtyDto specialtyDto);

    ///
    SpecialtyDto toSpecialtyDto(Specialty specialty);

    ///
    Collection!SpecialtyDto toSpecialtyDtos(Collection!Specialty specialties);

    ///
    Collection!Specialty toSpecialtys(Collection!SpecialtyDto specialties);
}

/// `SpecialtyMapperImpl`: the implementation MapStruct generates for `SpecialtyMapper`.
@Component class SpecialtyMapperImpl : SpecialtyMapper
{

    override Specialty toSpecialty(SpecialtyDto specialtyDto)
    {
        if (specialtyDto is null)
        {
            return null;
        }
        auto specialty = new Specialty();
        specialty.setId(unboxedId(specialtyDto.getId()));
        specialty.setName(specialtyDto.getName());
        return specialty;
    }

    override SpecialtyDto toSpecialtyDto(Specialty specialty)
    {
        if (specialty is null)
        {
            return null;
        }
        auto specialtyDto = new SpecialtyDto();
        specialtyDto.setId(boxedId(specialty.getId()));
        specialtyDto.setName(specialty.getName());
        return specialtyDto;
    }

    override Collection!SpecialtyDto toSpecialtyDtos(Collection!Specialty specialties)
    {
        if (specialties is null)
        {
            return null;
        }
        Collection!SpecialtyDto collection = new ArrayList!SpecialtyDto();
        foreach (specialty; specialties)
        {
            collection.add(toSpecialtyDto(specialty));
        }
        return collection;
    }

    override Collection!Specialty toSpecialtys(Collection!SpecialtyDto specialties)
    {
        if (specialties is null)
        {
            return null;
        }
        Collection!Specialty collection = new ArrayList!Specialty();
        foreach (specialtyDto; specialties)
        {
            collection.add(toSpecialty(specialtyDto));
        }
        return collection;
    }
}

/// `UserMapper`.
interface UserMapper
{
    ///
    Role toRole(RoleDto roleDto);

    ///
    RoleDto toRoleDto(Role role);

    ///
    Collection!RoleDto toRoleDtos(Collection!Role roles);

    ///
    User toUser(UserDto userDto);

    ///
    UserDto toUserDto(User user);

    ///
    Collection!Role toRoles(Collection!RoleDto roleDtos);
}

/// `UserMapperImpl`: the implementation MapStruct generates for `UserMapper`.
@Component class UserMapperImpl : UserMapper
{

    override Role toRole(RoleDto roleDto)
    {
        if (roleDto is null)
        {
            return null;
        }
        auto role = new Role();
        role.setName(roleDto.getName());
        return role;
    }

    override RoleDto toRoleDto(Role role)
    {
        if (role is null)
        {
            return null;
        }
        auto roleDto = new RoleDto();
        roleDto.setName(role.getName());
        return roleDto;
    }

    override Collection!RoleDto toRoleDtos(Collection!Role roles)
    {
        if (roles is null)
        {
            return null;
        }
        Collection!RoleDto collection = new ArrayList!RoleDto();
        foreach (role; roles)
        {
            collection.add(toRoleDto(role));
        }
        return collection;
    }

    override User toUser(UserDto userDto)
    {
        if (userDto is null)
        {
            return null;
        }
        auto user = new User();
        user.setUsername(userDto.getUsername());
        user.setPassword(userDto.getPassword());
        user.setEnabled(userDto.getEnabled());
        user.setRoles(roleDtoListToRoleSet(userDto.getRoles()));
        return user;
    }

    override UserDto toUserDto(User user)
    {
        if (user is null)
        {
            return null;
        }
        auto userDto = new UserDto();
        userDto.setUsername(user.getUsername());
        userDto.setPassword(user.getPassword());
        userDto.setEnabled(user.getEnabled());
        userDto.setRoles(roleSetToRoleDtoList(user.getRoles()));
        return userDto;
    }

    override Collection!Role toRoles(Collection!RoleDto roleDtos)
    {
        if (roleDtos is null)
        {
            return null;
        }
        Collection!Role collection = new ArrayList!Role();
        foreach (roleDto; roleDtos)
        {
            collection.add(toRole(roleDto));
        }
        return collection;
    }

    protected List!Role roleDtoListToRoleSet(List!RoleDto list)
    {
        if (list is null)
        {
            return null;
        }
        List!Role set = new ArrayList!Role();
        foreach (roleDto; list)
        {
            set.add(toRole(roleDto));
        }
        return set;
    }

    protected List!RoleDto roleSetToRoleDtoList(List!Role set)
    {
        if (set is null)
        {
            return null;
        }
        List!RoleDto list = new ArrayList!RoleDto();
        foreach (role; set)
        {
            list.add(toRoleDto(role));
        }
        return list;
    }
}

/// `VetMapper`.
interface VetMapper
{
    ///
    Vet toVet(VetDto vetDto);

    ///
    Vet toVet(VetFieldsDto vetFieldsDto);

    ///
    VetDto toVetDto(Vet vet);

    ///
    Collection!VetDto toVetDtos(Collection!Vet vets);
}

/// `VetMapperImpl`: the implementation MapStruct generates for `VetMapper`.
@Component class VetMapperImpl : VetMapper
{
    private SpecialtyMapper specialtyMapper;

    ///
    this(SpecialtyMapper specialtyMapper)
    {
        this.specialtyMapper = specialtyMapper;
    }

    override Vet toVet(VetDto vetDto)
    {
        if (vetDto is null)
        {
            return null;
        }
        auto vet = new Vet();
        vet.setId(unboxedId(vetDto.getId()));
        vet.setFirstName(vetDto.getFirstName());
        vet.setLastName(vetDto.getLastName());
        vet.setSpecialties(specialtyDtoListToSpecialtyList(vetDto.getSpecialties()));
        return vet;
    }

    override Vet toVet(VetFieldsDto vetFieldsDto)
    {
        if (vetFieldsDto is null)
        {
            return null;
        }
        auto vet = new Vet();
        vet.setFirstName(vetFieldsDto.getFirstName());
        vet.setLastName(vetFieldsDto.getLastName());
        vet.setSpecialties(specialtyDtoListToSpecialtyList(vetFieldsDto.getSpecialties()));
        return vet;
    }

    override VetDto toVetDto(Vet vet)
    {
        if (vet is null)
        {
            return null;
        }
        auto vetDto = new VetDto();
        vetDto.setFirstName(vet.getFirstName());
        vetDto.setLastName(vet.getLastName());
        vetDto.setSpecialties(specialtyListToSpecialtyDtoList(vet.getSpecialties()));
        vetDto.setId(boxedId(vet.getId()));
        return vetDto;
    }

    override Collection!VetDto toVetDtos(Collection!Vet vets)
    {
        if (vets is null)
        {
            return null;
        }
        Collection!VetDto collection = new ArrayList!VetDto();
        foreach (vet; vets)
        {
            collection.add(toVetDto(vet));
        }
        return collection;
    }

    protected List!Specialty specialtyDtoListToSpecialtyList(List!SpecialtyDto list)
    {
        if (list is null)
        {
            return null;
        }
        List!Specialty list1 = new ArrayList!Specialty();
        foreach (specialtyDto; list)
        {
            list1.add(specialtyMapper.toSpecialty(specialtyDto));
        }
        return list1;
    }

    protected List!SpecialtyDto specialtyListToSpecialtyDtoList(List!Specialty list)
    {
        if (list is null)
        {
            return null;
        }
        List!SpecialtyDto list1 = new ArrayList!SpecialtyDto();
        foreach (specialty; list)
        {
            list1.add(specialtyMapper.toSpecialtyDto(specialty));
        }
        return list1;
    }
}

/// `VisitMapper`.
interface VisitMapper
{
    ///
    Visit toVisit(VisitDto visitDto);

    ///
    Visit toVisit(VisitFieldsDto visitFieldsDto);

    ///
    VisitDto toVisitDto(Visit visit);

    ///
    Collection!VisitDto toVisitsDto(Collection!Visit visits);
}

/// `VisitMapperImpl`: the implementation MapStruct generates for `VisitMapper`.
@Component class VisitMapperImpl : VisitMapper
{

    override Visit toVisit(VisitDto visitDto)
    {
        if (visitDto is null)
        {
            return null;
        }
        auto visit = new Visit();
        visit.setPet(visitDtoToPet(visitDto));
        visit.setId(unboxedId(visitDto.getId()));
        visit.setDate(visitDto.getDate());
        visit.setDescription(visitDto.getDescription());
        return visit;
    }

    override Visit toVisit(VisitFieldsDto visitFieldsDto)
    {
        if (visitFieldsDto is null)
        {
            return null;
        }
        auto visit = new Visit();
        visit.setDate(visitFieldsDto.getDate());
        visit.setDescription(visitFieldsDto.getDescription());
        return visit;
    }

    override VisitDto toVisitDto(Visit visit)
    {
        if (visit is null)
        {
            return null;
        }
        auto visitDto = new VisitDto();
        visitDto.setPetId(boxedId(visitPetId(visit)));
        visitDto.setDate(visit.getDate());
        visitDto.setDescription(visit.getDescription());
        visitDto.setId(boxedId(visit.getId()));
        return visitDto;
    }

    override Collection!VisitDto toVisitsDto(Collection!Visit visits)
    {
        if (visits is null)
        {
            return null;
        }
        Collection!VisitDto collection = new ArrayList!VisitDto();
        foreach (visit; visits)
        {
            collection.add(toVisitDto(visit));
        }
        return collection;
    }

    protected Pet visitDtoToPet(VisitDto visitDto)
    {
        if (visitDto is null)
        {
            return null;
        }
        auto pet = new Pet();
        pet.setId(unboxedId(visitDto.getPetId()));
        return pet;
    }

    private int visitPetId(Visit visit)
    {
        auto pet = visit.getPet();
        if (pet is null)
        {
            return 0;
        }
        return pet.getId();
    }
}
