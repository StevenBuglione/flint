/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba): `org.springframework.samples.petclinic.security`,
ported to Flint. Copyright the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: Java → D syntax (R1); Java's lambda customizers are D delegates (R9).
`BasicAuthenticationConfig` (`petclinic.security.enable=true`) follows with the secured-mode goldens.
+/
module org.springframework.samples.petclinic.security;

import flint.boot.autoconfigure.condition : ConditionalOnProperty;
import flint.context.annotation : Bean, Configuration;
import flint.security.config.annotation.web.builders : HttpSecurity;
import flint.security.config.annotation.web.configuration : EnableWebSecurity;
import flint.security.config.annotation.web.configurers : AuthorizeHttpRequestsConfigurer,
    CsrfConfigurer, HeadersConfigurer;
import flint.security.web : SecurityFilterChain;
import flint.stereotype : Component;

@safe:

/// The role names `@PreAuthorize` expressions read as `@roles.OWNER_ADMIN` and so on.
@Component class Roles
{
    immutable string OWNER_ADMIN = "ROLE_OWNER_ADMIN"; ///
    immutable string VET_ADMIN = "ROLE_VET_ADMIN"; ///
    immutable string ADMIN = "ROLE_ADMIN"; ///
}

/// Security off (`petclinic.security.enable=false`, the default): every request is permitted, CSRF is off, and
/// Spring Security's default headers are written, with `X-Frame-Options: SAMEORIGIN`.
@Configuration @EnableWebSecurity @ConditionalOnProperty(name : ["petclinic.security.enable"], havingValue:
        "false")
class DisableSecurityConfig
{
    private alias Registry = AuthorizeHttpRequestsConfigurer.AuthorizationManagerRequestMatcherRegistry;

    ///
    @Bean SecurityFilterChain filterChain(HttpSecurity http)
    {
        return http.csrf((CsrfConfigurer csrf) { csrf.disable(); }).authorizeHttpRequests((Registry authz) {
            authz.anyRequest().permitAll();
        }).headers((HeadersConfigurer headers) {
            // to avoid setting of X-Frame-Options=deny header
            headers.frameOptions((HeadersConfigurer.FrameOptionsConfig frame) { frame.sameOrigin(); });
        }).build();
    }
}
