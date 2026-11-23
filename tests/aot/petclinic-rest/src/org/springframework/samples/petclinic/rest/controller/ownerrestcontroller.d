/// `OwnerRestController`: implements the generated `OwnersApi`, and secures each method.
module org.springframework.samples.petclinic.rest.controller.ownerrestcontroller;

import flint.http : ResponseEntity;
import flint.security.access.prepost : PreAuthorize;
import flint.web.bind.annotation : CrossOrigin, RequestMapping, RestController;
import org.springframework.samples.petclinic.rest.api.ownersapi : OwnersApi;
import org.springframework.samples.petclinic.rest.dto.ownerdto : OwnerFieldsDto;
import org.springframework.samples.petclinic.service.clinicservice : ClinicService;

@safe:

/// The owners controller.
@RestController @CrossOrigin(exposedHeaders: ["errors, content-type"]) @RequestMapping("/api")
class OwnerRestController : OwnersApi
{
    private ClinicService clinicService;

    /// Constructor injection.
    this(ClinicService clinicService)
    {
        this.clinicService = clinicService;
    }

    /// GET /api/owners/{ownerId}.
    @PreAuthorize("hasRole(@roles.OWNER_ADMIN)") ResponseEntity getOwner(int ownerId)
    {
        return ResponseEntity.ok().build();
    }

    /// POST /api/owners.
    @PreAuthorize("hasRole(@roles.OWNER_ADMIN)") ResponseEntity addOwner(OwnerFieldsDto ownerFieldsDto)
    {
        return ResponseEntity.ok().build();
    }
}
