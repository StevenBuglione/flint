/// `ClinicService` and its transactional implementation.
module org.springframework.samples.petclinic.service.clinicservice;

import flint.stereotype : Service;
import flint.transaction.annotation : Transactional;
import org.springframework.samples.petclinic.model.baseentity : Owner;

@safe:

/// The use cases.
interface ClinicService
{
    /// An owner by id, or null.
    Owner findOwnerById(int id);
}

/// `@Service public class ClinicServiceImpl`.
@Service class ClinicServiceImpl : ClinicService
{
    /// Read-only transaction.
    @Transactional(readOnly: true) Owner findOwnerById(int id)
    {
        auto owner = new Owner;
        owner.setId(id);
        return owner;
    }
}
