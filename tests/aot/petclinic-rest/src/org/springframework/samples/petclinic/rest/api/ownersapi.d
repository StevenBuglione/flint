/// `OwnersApi`, the interface openapi-generator writes: the mappings live on its methods.
module org.springframework.samples.petclinic.rest.api.ownersapi;

import flint.http : ResponseEntity;
import flint.java.util : List, Optional;
import flint.jakarta.validation : Valid;
import flint.web.bind.annotation : GetMapping, PathVariable, PostMapping, RequestBody, RequestParam;
import org.springframework.samples.petclinic.rest.dto.ownerdto : OwnerFieldsDto;

@safe:

/// The owners resource.
interface OwnersApi
{
    /// GET /owners/{ownerId}.
    @GetMapping(path: ["/owners/{ownerId}"], produces: ["application/json"])
    ResponseEntity getOwner(@PathVariable("ownerId") int ownerId);

    /// GET /owners?lastName=...&ids=...: optional and multi-valued request parameters.
    @GetMapping(path: ["/owners"], produces: ["application/json"])
    ResponseEntity listOwners(@RequestParam(value: "lastName", required: false) Optional!string lastName,
            @RequestParam(value: "ids", required: false) List!int ids);

    /// POST /owners.
    @PostMapping(path: ["/owners"], produces: ["application/json"])
    ResponseEntity addOwner(@Valid @RequestBody OwnerFieldsDto ownerFieldsDto);
}
