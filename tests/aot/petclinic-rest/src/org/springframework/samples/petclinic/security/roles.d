/// `Roles`: the role names `@PreAuthorize` expressions read as `@roles.OWNER_ADMIN`.
module org.springframework.samples.petclinic.security.roles;

import flint.stereotype : Component;

@safe:

/// `@Component("roles") public class Roles`.
@Component("roles") class Roles
{
    /// Owner administration.
    string OWNER_ADMIN = "ROLE_OWNER_ADMIN";
}
