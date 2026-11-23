/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba): `org.springframework.samples.petclinic.security`,
ported to Flint. Copyright the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: Java → D syntax (R1). `DisableSecurityConfig` and `BasicAuthenticationConfig` join
when Boot's SecurityAutoConfiguration provides `HttpSecurity` (with `@EnableWebSecurity`).
+/
module org.springframework.samples.petclinic.security;

import flint.stereotype : Component;

@safe:

/// The role names `@PreAuthorize` expressions read as `@roles.OWNER_ADMIN` and so on.
@Component class Roles
{
    immutable string OWNER_ADMIN = "ROLE_OWNER_ADMIN"; ///
    immutable string VET_ADMIN = "ROLE_VET_ADMIN"; ///
    immutable string ADMIN = "ROLE_ADMIN"; ///
}
