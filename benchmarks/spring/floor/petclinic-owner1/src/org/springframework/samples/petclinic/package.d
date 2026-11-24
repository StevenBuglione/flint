/++
The floor program's Boot application (arm "mapped"). It sits in petclinic-rest's root package, as petclinic's own
PetClinicApplication does, so its component scan covers the petclinic packages this project links (model, mapper,
rest.dto, rest.validation) and Flint AOT describes them as it does for petclinic-rest.
+/
module org.springframework.samples.petclinic;

import flint.boot : FlintMain;
import flint.boot.autoconfigure : FlintBootApplication;
import org.springframework.floor.app : runFloor;

@safe:

/// Petclinic-rest's mappers and Boot's Jackson auto-configuration, without a web server.
@FlintBootApplication
class FloorApplication
{
    /// Run the selected arm.
    static int main(string[] args)
    {
        return runFloor!FloorApplication(args);
    }
}

mixin FlintMain!FloorApplication;
