/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba): `org.springframework.samples.petclinic.security`,
ported to Flint. Copyright the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: Java → D syntax (R1); Java's lambda customizers are D delegates (R9).
`BasicAuthenticationConfig`'s `@Autowired` field and `configureGlobal` method are constructor-injected, as the
port's other `@Autowired` fields are.
+/
module org.springframework.samples.petclinic.security;

import flint.boot.autoconfigure.condition : ConditionalOnProperty;
import flint.context.annotation : Bean, Configuration;
import flint.javax.sql : DataSource;
import flint.security.config : Customizer;
import flint.security.config.annotation.authentication.builders : AuthenticationManagerBuilder;
import flint.security.config.annotation.method.configuration : EnableMethodSecurity;
import flint.security.config.annotation.web.builders : HttpSecurity;
import flint.security.config.annotation.web.configuration : EnableWebSecurity;
import flint.security.config.annotation.web.configurers : AuthorizeHttpRequestsConfigurer,
    CsrfConfigurer, HeadersConfigurer, HttpBasicConfigurer;
import flint.security.crypto.bcrypt : BCryptPasswordEncoder;
import flint.security.crypto.password : PasswordEncoder;
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

/// Security on (`petclinic.security.enable=true`): HTTP Basic against the `users` and `roles` tables with BCrypt
/// passwords, and `@PreAuthorize` method security.
@Configuration @EnableMethodSecurity(prePostEnabled : true)  // Enable @PreAuthorize method-level security
@ConditionalOnProperty(name : ["petclinic.security.enable"], havingValue:
        "true")
class BasicAuthenticationConfig
{
    private alias Registry = AuthorizeHttpRequestsConfigurer.AuthorizationManagerRequestMatcherRegistry;

    private DataSource dataSource;

    /// `@Autowired private DataSource dataSource` and `@Autowired configureGlobal(auth)`.
    this(DataSource dataSource, AuthenticationManagerBuilder auth)
    {
        this.dataSource = dataSource;
        configureGlobal(auth);
    }

    ///
    @Bean PasswordEncoder passwordEncoder()
    {
        return new BCryptPasswordEncoder();
    }

    ///
    @Bean SecurityFilterChain filterChain(HttpSecurity http)
    {
        http.csrf((CsrfConfigurer csrf) { csrf.disable(); }).authorizeHttpRequests((Registry authz) {
            authz.anyRequest().authenticated();
        }).httpBasic(Customizer!HttpBasicConfigurer.withDefaults());
        return http.build();
    }

    ///
    final void configureGlobal(AuthenticationManagerBuilder auth)
    {
        auth.jdbcAuthentication().dataSource(dataSource)
            .usersByUsernameQuery("select username,password,enabled from users where username=?")
            .authoritiesByUsernameQuery("select username,role from roles where username=?");
    }
}
