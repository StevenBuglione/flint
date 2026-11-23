# Spring Security subset for spring-petclinic-rest (work-queue item 24)

framework-core ports the part of Spring Security 7.2.0 that spring-petclinic-rest uses, for the `flint-security` repo
(an integrated repo: boot → security → framework), staged under `security/` with `"repo": "security"` in
`policy/framework.json`; at extraction `security/<x>` becomes `flint-<x>` in flint-security.

## What petclinic-rest uses

- `BasicAuthenticationConfig` (when `petclinic.security.enable=true`): `@EnableMethodSecurity(prePostEnabled =
  true)`, a `BCryptPasswordEncoder` bean, `http.csrf(disable).authorizeHttpRequests(anyRequest().authenticated())
  .httpBasic(withDefaults())`, and `@Autowired configureGlobal(AuthenticationManagerBuilder)` with
  `jdbcAuthentication()` over its `users` and `roles` tables.
- `DisableSecurityConfig` (the default, `false`): `csrf(disable)`, `anyRequest().permitAll()`, and
  `headers(frameOptions(sameOrigin))`. Spring Security still writes its default response headers, which the suite
  checks on every response.
- The controllers: `@PreAuthorize("hasRole(@roles.OWNER_ADMIN)")` and `VET_ADMIN`, with a `Roles` bean.

## Modules

| DUB package | D modules |
| --- | --- |
| `flint:security-crypto` | `flint.security.crypto.password` (`PasswordEncoder`, `DelegatingPasswordEncoder`, `NoOpPasswordEncoder`), `.bcrypt` (`BCryptPasswordEncoder` over a registered backend), `.factory` |
| `flint:security-core` | `flint.security.core` (`Authentication`, `GrantedAuthority`, `AuthorityUtils`), `.core.context` (`SecurityContextHolder` on `FiberLocal`), `.core.userdetails` (`User`, `UserDetailsService`; `.jdbc`: `JdbcDaoImpl`), `flint.security.authentication` (`ProviderManager`, tokens; `.dao`: `DaoAuthenticationProvider`), `flint.security.access` (`.prepost`: `PreAuthorize`; `.expression`: `SecurityExpressionRoot`), `flint.security.authorization` (`.method`: the `@PreAuthorize` advisor), `flint.security.provisioning` |
| `flint:security-web` | `flint.security.web` (`FilterChainProxy`, `SecurityFilterChain`), `.header`, `.context`, `.authentication` (`.www`: HTTP Basic), `.access` (exception translation, `AuthorizationFilter`), `.csrf`, `.util.matcher` |
| `flint:security-config` | `flint.security.config` (`Customizer`), `.annotation.web.builders` (`HttpSecurity`), `.annotation.web.configurers`, `.annotation.web.configuration` (`@EnableWebSecurity`), `.annotation.authentication` (`AuthenticationManagerBuilder`, `AuthenticationConfiguration`), `.annotation.method.configuration` (`@EnableMethodSecurity`) |

## Decisions

- **Method security** runs on Flint AOT's proxy chain: `PreAuthorizeMethodInterceptor` is an `Advisor` (order 200,
  Spring's `PRE_AUTHORIZE`) that evaluates the expression Flint AOT compiled for the method (contract 3) over a
  `MethodSecurityExpressionRoot`, an `EvaluationContext` with Spring's root functions and properties. It is a bean
  only under `@EnableMethodSecurity`, so with `petclinic.security.enable=false` the proxies just proceed.
- **The security context** lives in a `FiberLocal`, so each request fiber has its own. There is no HTTP session
  repository; a context lasts for one request and its dispatches.
- **Headers** are written before the chain runs (Spring's `shouldWriteHeadersEagerly`). The response is the same
  unless the application sets `Cache-Control`, `Expires` or `Pragma` itself; web-http's response wrappers now allow
  Spring's lazy writing, which is a follow-up.
- **CSRF** has no token repositories: with CSRF on, unsafe methods are denied (403). Both petclinic configurations
  disable it.
- **BCrypt** is not implemented here: AGENTS.md forbids a new cryptographic implementation. `BCryptPasswordEncoder`
  checks the format and delegates hashing to a `BCryptBackend` that a pinned native provider registers. Choosing that
  provider is open for the owner (`decisions.md`).
- Not ported: form login, logout, sessions, remember-me, the request cache, CORS, OAuth2, SAML, `@Secured`, JSR-250,
  `@PostAuthorize` interceptor, the firewall.

## Open

- Framework budgets and probes for the four modules (size-levers).
- `@Import` through `@EnableWebSecurity`/`@EnableMethodSecurity` in the generator (flint-aot).
- Boot: `SecurityAutoConfiguration`, `SecurityFilterAutoConfiguration` and `UserDetailsServiceAutoConfiguration`.
- Secured-mode goldens for petclinic-rest (proof-harness), and the BCrypt provider.
