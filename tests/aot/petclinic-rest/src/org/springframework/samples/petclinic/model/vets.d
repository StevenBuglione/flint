/// `Vets`, made by a `FactoryBean`, so `getBean(Vets)` must find the factory's object.
module org.springframework.samples.petclinic.model.vets;

import flint.beans.factory : FactoryBean;
import flint.stereotype : Component;

@safe:

/// The vets list.
class Vets
{
}

/// A factory bean for `Vets`.
@Component final class VetsFactory : FactoryBean!Vets
{
    mixin FactoryBean!Vets.Defaults;

    /// The object.
    Vets getObject()
    {
        return new Vets;
    }
}
