/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba): `org.springframework.samples.petclinic.rest.api`, the
interfaces openapi-generator 7.26.0 (SpringCodegen, `interfaceOnly`) writes from src/main/resources/openapi.yml at
build time, translated to D.
Copyright the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors:
- One module for the generated package (R1). `ResponseEntity<T>` is Flint's `ResponseEntity`, whose body is an
  `Any` (R4).
- The generated default bodies, which answer 501 with an example from openapi.yml, are dropped: every interface is
  implemented by a controller, so a method is abstract. `OopsApi`, which no controller implements, and `ApiUtil`
  are omitted, as are the springdoc annotations (`@Tag`, `@Operation`, `@Parameter`).
+/
module org.springframework.samples.petclinic.rest.api;

import flint.http : ResponseEntity;
import flint.jakarta.validation : Valid;
import flint.jakarta.validation.constraints : Max, Min;
import flint.validation.annotation : Validated;
import flint.web.bind.annotation : PathVariable, RequestBody, RequestMapping, RequestMethod, RequestParam;
import org.springframework.samples.petclinic.rest.dto : OwnerFieldsDto, PetDto, PetFieldsDto,
    PetTypeDto, PetTypeFieldsDto, SpecialtyDto, UserDto, VetDto, VetFieldsDto, VisitDto, VisitFieldsDto;

@safe:

/// `OwnersApi`.
@Validated
interface OwnersApi
{
    /// POST /owners: Adds a pet owner
    @RequestMapping(method : [RequestMethod.POST], value:
            ["/owners"], produces:
            ["application/json"], consumes:
            ["application/json"])
    ResponseEntity addOwner(@Valid @RequestBody OwnerFieldsDto ownerFieldsDto);

    /// POST /owners/{ownerId}/pets: Adds a pet to an owner
    @RequestMapping(method : [RequestMethod.POST], value:
            ["/owners/{ownerId}/pets"], produces:
            ["application/json"], consumes:
            ["application/json"])
    ResponseEntity addPetToOwner(@Min(0) @PathVariable("ownerId") int ownerId,
            @Valid @RequestBody PetFieldsDto petFieldsDto);

    /// POST /owners/{ownerId}/pets/{petId}/visits: Adds a vet visit
    @RequestMapping(method : [RequestMethod.POST], value:
            ["/owners/{ownerId}/pets/{petId}/visits"],
produces:
            ["application/json"], consumes:
            ["application/json"])
    ResponseEntity addVisitToOwner(@Min(0) @PathVariable("ownerId") int ownerId,
            @Min(0) @PathVariable("petId") int petId, @Valid @RequestBody VisitFieldsDto visitFieldsDto);

    /// DELETE /owners/{ownerId}: Delete an owner by ID
    @RequestMapping(method : [RequestMethod.DELETE], value:
            ["/owners/{ownerId}"], produces:
            ["application/json"])
    ResponseEntity deleteOwner(@Min(0) @PathVariable("ownerId") int ownerId);

    /// GET /owners/{ownerId}: Get a pet owner by ID
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/owners/{ownerId}"], produces:
            ["application/json"])
    ResponseEntity getOwner(@Min(0) @PathVariable("ownerId") int ownerId);

    /// GET /owners/{ownerId}/pets/{petId}: Get a pet by ID
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/owners/{ownerId}/pets/{petId}"],
produces:
            ["application/json"])
    ResponseEntity getOwnersPet(@Min(0) @PathVariable("ownerId") int ownerId, @Min(0) @PathVariable("petId") int petId);

    /// GET /owners: Lists pet owners
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/owners"], produces:
            ["application/json"])
    ResponseEntity listOwners(@RequestParam(value : "lastName", required:
            false) string lastName);

    /// PUT /owners/{ownerId}: Update a pet owner's details
    @RequestMapping(method : [RequestMethod.PUT], value:
            ["/owners/{ownerId}"], produces:
            ["application/json"], consumes:
            ["application/json"])
    ResponseEntity updateOwner(@Min(0) @PathVariable("ownerId") int ownerId,
            @Valid @RequestBody OwnerFieldsDto ownerFieldsDto);

    /// PUT /owners/{ownerId}/pets/{petId}: Update a pet's details
    @RequestMapping(method : [RequestMethod.PUT], value:
            ["/owners/{ownerId}/pets/{petId}"],
produces:
            ["application/json"], consumes:
            ["application/json"])
    ResponseEntity updateOwnersPet(@Min(0) @PathVariable("ownerId") int ownerId,
            @Min(0) @PathVariable("petId") int petId, @Valid @RequestBody PetFieldsDto petFieldsDto);
}

/// `OwnerV2Api`.
@Validated
interface OwnerV2Api
{
    /// GET /v2/owners: Lists pet owners with pagination
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/v2/owners"], produces:
            ["application/json"])
    ResponseEntity listOwnersPage(@RequestParam(value : "lastName", required:
            false) string lastName,
            @Min(0) @RequestParam(value : "page", required:
                false, defaultValue:
                "0") int page, @Max(100) @Min(1) @RequestParam(value : "size", required:
                false,
defaultValue:
                "20") int size);
}

/// `PetsApi`.
@Validated
interface PetsApi
{
    /// DELETE /pets/{petId}: Delete a pet by ID
    @RequestMapping(method : [RequestMethod.DELETE], value:
            ["/pets/{petId}"], produces:
            ["application/json"])
    ResponseEntity deletePet(@Min(0) @PathVariable("petId") int petId);

    /// GET /pets/{petId}: Get a pet by ID
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/pets/{petId}"], produces:
            ["application/json"])
    ResponseEntity getPet(@Min(0) @PathVariable("petId") int petId);

    /// GET /pets: Lists pet
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/pets"], produces:
            ["application/json"])
    ResponseEntity listPets();

    /// PUT /pets/{petId}: Update a pet by ID
    @RequestMapping(method : [RequestMethod.PUT], value:
            ["/pets/{petId}"], produces:
            ["application/json"], consumes:
            ["application/json"])
    ResponseEntity updatePet(@Min(0) @PathVariable("petId") int petId, @Valid @RequestBody PetDto petDto);
}

/// `PetV2Api`.
@Validated
interface PetV2Api
{
    /// GET /v2/pets: Lists pets with pagination.
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/v2/pets"], produces:
            ["application/json"])
    ResponseEntity listPetsPage(@Min(0) @RequestParam(value : "page", required:
            false,
defaultValue:
            "0") int page, @Max(100) @Min(1) @RequestParam(value : "size", required:
            false,
defaultValue:
            "20") int size);
}

/// `PettypesApi`.
@Validated
interface PettypesApi
{
    /// POST /pettypes: Create a pet type
    @RequestMapping(method : [RequestMethod.POST], value:
            ["/pettypes"], produces:
            ["application/json"], consumes:
            ["application/json"])
    ResponseEntity addPetType(@Valid @RequestBody PetTypeFieldsDto petTypeFieldsDto);

    /// DELETE /pettypes/{petTypeId}: Delete a pet type by ID
    @RequestMapping(method : [RequestMethod.DELETE], value:
            ["/pettypes/{petTypeId}"], produces:
            ["application/json"])
    ResponseEntity deletePetType(@Min(0) @PathVariable("petTypeId") int petTypeId);

    /// GET /pettypes/{petTypeId}: Get a pet type by ID
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/pettypes/{petTypeId}"], produces:
            ["application/json"])
    ResponseEntity getPetType(@Min(0) @PathVariable("petTypeId") int petTypeId);

    /// GET /pettypes: Lists pet types
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/pettypes"], produces:
            ["application/json"])
    ResponseEntity listPetTypes();

    /// PUT /pettypes/{petTypeId}: Update a pet type by ID
    @RequestMapping(method : [RequestMethod.PUT], value:
            ["/pettypes/{petTypeId}"], produces:
            ["application/json"], consumes:
            ["application/json"])
    ResponseEntity updatePetType(@Min(0) @PathVariable("petTypeId") int petTypeId,
            @Valid @RequestBody PetTypeDto petTypeDto);
}

/// `SpecialtiesApi`.
@Validated
interface SpecialtiesApi
{
    /// POST /specialties: Create a specialty
    @RequestMapping(method : [RequestMethod.POST], value:
            ["/specialties"], produces:
            ["application/json"], consumes:
            ["application/json"])
    ResponseEntity addSpecialty(@Valid @RequestBody SpecialtyDto specialtyDto);

    /// DELETE /specialties/{specialtyId}: Delete a specialty by ID
    @RequestMapping(method : [RequestMethod.DELETE], value:
            ["/specialties/{specialtyId}"],
produces:
            ["application/json"])
    ResponseEntity deleteSpecialty(@Min(0) @PathVariable("specialtyId") int specialtyId);

    /// GET /specialties/{specialtyId}: Get a specialty by ID
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/specialties/{specialtyId}"],
produces:
            ["application/json"])
    ResponseEntity getSpecialty(@Min(0) @PathVariable("specialtyId") int specialtyId);

    /// GET /specialties: Lists specialties
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/specialties"], produces:
            ["application/json"])
    ResponseEntity listSpecialties();

    /// PUT /specialties/{specialtyId}: Update a specialty by ID
    @RequestMapping(method : [RequestMethod.PUT], value:
            ["/specialties/{specialtyId}"], produces:
            ["application/json"], consumes:
            ["application/json"])
    ResponseEntity updateSpecialty(@Min(0) @PathVariable("specialtyId") int specialtyId,
            @Valid @RequestBody SpecialtyDto specialtyDto);
}

/// `UsersApi`.
@Validated
interface UsersApi
{
    /// POST /users: Create a user
    @RequestMapping(method : [RequestMethod.POST], value:
            ["/users"], produces:
            ["application/json"], consumes:
            ["application/json"])
    ResponseEntity addUser(@Valid @RequestBody UserDto userDto);
}

/// `VetsApi`.
@Validated
interface VetsApi
{
    /// POST /vets: Create a Vet
    @RequestMapping(method : [RequestMethod.POST], value:
            ["/vets"], produces:
            ["application/json"],
consumes:
            ["application/json"])
    ResponseEntity addVet(@Valid @RequestBody VetDto vetDto);

    /// DELETE /vets/{vetId}: Delete a vet by ID
    @RequestMapping(method : [RequestMethod.DELETE], value:
            ["/vets/{vetId}"], produces:
            ["application/json"])
    ResponseEntity deleteVet(@Min(0) @PathVariable("vetId") int vetId);

    /// GET /vets/{vetId}: Get a vet by ID
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/vets/{vetId}"], produces:
            ["application/json"])
    ResponseEntity getVet(@Min(0) @PathVariable("vetId") int vetId);

    /// GET /vets: Lists vets
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/vets"], produces:
            ["application/json"])
    ResponseEntity listVets();

    /// PUT /vets/{vetId}: Update a vet  by ID
    @RequestMapping(method : [RequestMethod.PUT], value:
            ["/vets/{vetId}"], produces:
            ["application/json"], consumes:
            ["application/json"])
    ResponseEntity updateVet(@Min(0) @PathVariable("vetId") int vetId, @Valid @RequestBody VetDto vetDto);
}

/// `VisitsApi`.
@Validated
interface VisitsApi
{
    /// POST /visits: Create a visit
    @RequestMapping(method : [RequestMethod.POST], value:
            ["/visits"], produces:
            ["application/json"], consumes:
            ["application/json"])
    ResponseEntity addVisit(@Valid @RequestBody VisitDto visitDto);

    /// DELETE /visits/{visitId}: Delete a visit by ID
    @RequestMapping(method : [RequestMethod.DELETE], value:
            ["/visits/{visitId}"], produces:
            ["application/json"])
    ResponseEntity deleteVisit(@Min(0) @PathVariable("visitId") int visitId);

    /// GET /visits/{visitId}: Get a visit by ID
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/visits/{visitId}"], produces:
            ["application/json"])
    ResponseEntity getVisit(@Min(0) @PathVariable("visitId") int visitId);

    /// GET /visits: Lists visits
    @RequestMapping(method : [RequestMethod.GET], value:
            ["/visits"], produces:
            ["application/json"])
    ResponseEntity listVisits();

    /// PUT /visits/{visitId}: Update a visit by ID
    @RequestMapping(method : [RequestMethod.PUT], value:
            ["/visits/{visitId}"], produces:
            ["application/json"], consumes:
            ["application/json"])
    ResponseEntity updateVisit(@Min(0) @PathVariable("visitId") int visitId,
            @Valid @RequestBody VisitFieldsDto visitFieldsDto);
}
