/// petclinic-rest's `BasicAuthenticationConfig`: method security only when petclinic.security.enable=true.
module org.springframework.samples.petclinic.security.basicauthenticationconfig;

import flint.boot.autoconfigure.condition : ConditionalOnProperty;
import flint.context.annotation : Configuration;
import flint.security.config.annotation.method.configuration : EnableMethodSecurity;

@safe:

/// `@EnableMethodSecurity` imports PrePostMethodSecurityConfiguration, under this class's condition.
@Configuration @EnableMethodSecurity @ConditionalOnProperty(name: ["petclinic.security.enable"], havingValue: "true")
class BasicAuthenticationConfig
{
}
