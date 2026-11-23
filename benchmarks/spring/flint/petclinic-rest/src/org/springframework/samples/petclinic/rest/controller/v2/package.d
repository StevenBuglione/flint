/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba): `org.springframework.samples.petclinic.rest.controller.v2`,
the paged listings, ported to Flint. Copyright the original author or authors. Licensed under the Apache License,
Version 2.0.
Modified by the Flint authors: Java → D syntax (R1). `Integer page` and `size` are `int`s that the request parameter
defaults fill, so Java's null checks fall away; the `@PreAuthorize` annotations wait on flint-security, as in `v1`.
+/
module org.springframework.samples.petclinic.rest.controller.v2;

import flint.data.domain : Page, PageRequest, Sort;
import flint.http : HttpStatus, ResponseEntity;
import flint.web.bind.annotation : CrossOrigin, RequestMapping, RestController;
import org.springframework.samples.petclinic.mapper : OwnerMapper, PetMapper;
import org.springframework.samples.petclinic.model : Owner, Pet;
import org.springframework.samples.petclinic.rest.api : OwnerV2Api, PetV2Api;
import org.springframework.samples.petclinic.service : ClinicService;

@safe:

/// `OwnerRestControllerV2`.
@RestController
@CrossOrigin(exposedHeaders : ["errors, content-type"])
@RequestMapping("/api")
class OwnerRestControllerV2 : OwnerV2Api
{
    private ClinicService clinicService;
    private OwnerMapper ownerMapper;

    ///
    this(ClinicService clinicService, OwnerMapper ownerMapper)
    {
        this.clinicService = clinicService;
        this.ownerMapper = ownerMapper;
    }

    override ResponseEntity listOwnersPage(string lastName, int page, int size)
    {
        Page!Owner owners = this.clinicService.findOwners(lastName, PageRequest.of(page, size, Sort.by("id")));
        return ResponseEntity.of(ownerMapper.toOwnerPageDto(owners), HttpStatus.OK);
    }
}

/// `PetRestControllerV2`.
@RestController
@CrossOrigin(exposedHeaders : ["errors, content-type"])
@RequestMapping("/api")
class PetRestControllerV2 : PetV2Api
{
    private ClinicService clinicService;
    private PetMapper petMapper;

    ///
    this(ClinicService clinicService, PetMapper petMapper)
    {
        this.clinicService = clinicService;
        this.petMapper = petMapper;
    }

    override ResponseEntity listPetsPage(int page, int size)
    {
        Page!Pet pets = this.clinicService.findPets(PageRequest.of(page, size, Sort.by("id")));
        return ResponseEntity.of(petMapper.toPetPageDto(pets), HttpStatus.OK);
    }
}
