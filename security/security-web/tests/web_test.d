module flint.security.web_test;

import flint.engine.aot.any : Any;
import flint.jakarta.servlet : Filter, FilterChain, ServletRequest, ServletResponse;
import flint.mock.web : MockHttpServletRequest, MockHttpServletResponse;
import flint.security.authentication : ProviderManager;
import flint.security.authentication.dao : DaoAuthenticationProvider;
import flint.security.authorization : AuthenticatedAuthorizationManager, SingleResultAuthorizationManager;
import flint.security.core : Authentication, AuthorityUtils;
import flint.security.core.authority : FactorGrantedAuthority;
import flint.security.core.context : SecurityContextHolder;
import flint.security.core.userdetails : User;
import flint.security.crypto.password : NoOpPasswordEncoder;
import flint.security.provisioning : InMemoryUserDetailsManager;
import flint.security.web : DefaultSecurityFilterChain, FilterChainProxy, SecurityFilterChain;
import flint.security.web.access : AuthorizationFilter, ExceptionTranslationFilter,
    RequestAuthorizationContext, RequestMatcherDelegatingAuthorizationManager;
import flint.security.web.authentication : AnonymousAuthenticationFilter;
import flint.security.web.authentication.www : BasicAuthenticationEntryPoint, BasicAuthenticationFilter;
import flint.security.web.context : RequestAttributeSecurityContextRepository, SecurityContextHolderFilter;
import flint.security.web.header : CacheControlHeadersWriter, HeaderWriterFilter,
    XContentTypeOptionsHeaderWriter, XFrameOptionsHeaderWriter, XXssProtectionHeaderWriter;
import flint.security.web.util.matcher : AnyRequestMatcher;

@safe:

/// The servlet at the end of the chain: records the authentication it ran with.
private final class Endpoint : FilterChain
{
    bool called;
    Authentication seen;

    void doFilter(ServletRequest, ServletResponse)
    {
        called = true;
        seen = SecurityContextHolder.getContext().getAuthentication();
    }
}

private HeaderWriterFilter headers(XFrameOptionsHeaderWriter.XFrameOptionsMode frame)
{
    return new HeaderWriterFilter(new XContentTypeOptionsHeaderWriter, new XXssProtectionHeaderWriter,
            new CacheControlHeadersWriter, new XFrameOptionsHeaderWriter(frame));
}

@("Security filter chains own their input arrays and getter snapshots")
unittest
{
    auto filter = headers(XFrameOptionsHeaderWriter.XFrameOptionsMode.DENY);
    Filter[] filters = [filter];
    auto chain = new DefaultSecurityFilterChain(AnyRequestMatcher.INSTANCE(), filters);
    SecurityFilterChain[] chains = [chain];
    auto proxy = new FilterChainProxy(chains);

    filters[0] = null;
    chains[0] = null;
    auto filtersSnapshot = chain.getFilters();
    auto chainsSnapshot = proxy.getFilterChains();
    assert(filtersSnapshot[0] is filter);
    assert(chainsSnapshot[0] is chain);

    filtersSnapshot[0] = null;
    chainsSnapshot[0] = null;
    assert(chain.getFilters()[0] is filter);
    assert(proxy.getFilterChains()[0] is chain);
    assert(new FilterChainProxy().getFilterChains() is null);
}

/// petclinic's DisableSecurityConfig: csrf off, permitAll, frame options SAMEORIGIN.
private FilterChainProxy disabledChain()
{
    auto rules = new RequestMatcherDelegatingAuthorizationManager;
    rules.add(AnyRequestMatcher.INSTANCE(), SingleResultAuthorizationManager!RequestAuthorizationContext.permitAll());
    Filter[] filters = [
        new SecurityContextHolderFilter(new RequestAttributeSecurityContextRepository),
        headers(XFrameOptionsHeaderWriter.XFrameOptionsMode.SAMEORIGIN),
        new AnonymousAuthenticationFilter("key"),
        new ExceptionTranslationFilter(new BasicAuthenticationEntryPoint),
        new AuthorizationFilter(rules)
    ];
    return new FilterChainProxy(new DefaultSecurityFilterChain(AnyRequestMatcher.INSTANCE(), filters));
}

/// petclinic's BasicAuthenticationConfig: csrf off, anyRequest().authenticated(), httpBasic.
private FilterChainProxy securedChain()
{
    auto users = new InMemoryUserDetailsManager(new User("admin", "admin",
            AuthorityUtils.createAuthorityList("ROLE_OWNER_ADMIN", "ROLE_VET_ADMIN", "ROLE_ADMIN")));
    auto provider = new DaoAuthenticationProvider(users);
    provider.setPasswordEncoder(NoOpPasswordEncoder.getInstance());
    auto entryPoint = new BasicAuthenticationEntryPoint;
    entryPoint.setRealmName("Realm");
    auto basic = new BasicAuthenticationFilter(new ProviderManager(provider), entryPoint);
    auto repository = new RequestAttributeSecurityContextRepository;
    basic.setSecurityContextRepository(repository);
    auto rules = new RequestMatcherDelegatingAuthorizationManager;
    rules.add(AnyRequestMatcher.INSTANCE(),
            AuthenticatedAuthorizationManager!RequestAuthorizationContext.authenticated());
    Filter[] filters = [
        new SecurityContextHolderFilter(repository),
        headers(XFrameOptionsHeaderWriter.XFrameOptionsMode.DENY), basic,
        new AnonymousAuthenticationFilter("key"), new ExceptionTranslationFilter(entryPoint),
        new AuthorizationFilter(rules)
    ];
    return new FilterChainProxy(new DefaultSecurityFilterChain(AnyRequestMatcher.INSTANCE(), filters));
}

private MockHttpServletRequest request(string authorization = null)
{
    auto request = new MockHttpServletRequest("GET", "/petclinic/api/owners");
    request.setServletPath("/api/owners");
    if (authorization !is null)
        request.addHeader("Authorization", authorization);
    return request;
}

unittest
{
    // Security disabled: every request passes anonymously, with Spring Security's default headers.
    auto endpoint = new Endpoint;
    auto response = new MockHttpServletResponse;
    disabledChain().doFilter(request(), response, endpoint);
    assert(endpoint.called && endpoint.seen.getName() == "anonymousUser");
    assert(response.getHeader("X-Content-Type-Options") == "nosniff");
    assert(response.getHeader("X-XSS-Protection") == "0");
    assert(response.getHeader("Cache-Control") == "no-cache, no-store, max-age=0, must-revalidate");
    assert(response.getHeader("Pragma") == "no-cache" && response.getHeader("Expires") == "0");
    assert(response.getHeader("X-Frame-Options") == "SAMEORIGIN");
    assert(SecurityContextHolder.getContext().getAuthentication() is null); // cleared after the request
}

unittest
{
    // Secured: no credentials and wrong credentials get 401 with the Basic challenge; good ones pass.
    auto chain = securedChain();
    auto endpoint = new Endpoint;
    auto response = new MockHttpServletResponse;
    chain.doFilter(request(), response, endpoint);
    assert(!endpoint.called && response.getStatus() == 401 && response.getErrorMessage() == "Unauthorized");
    assert(response.getHeader("WWW-Authenticate") == "Basic realm=\"Realm\"");
    assert(response.getHeader("X-Frame-Options") == "DENY");

    response = new MockHttpServletResponse;
    chain.doFilter(request("Basic YWRtaW46d3Jvbmc="), response, endpoint); // admin:wrong
    assert(!endpoint.called && response.getStatus() == 401);

    response = new MockHttpServletResponse;
    chain.doFilter(request("Basic YWRtaW46YWRtaW4="), response, endpoint); // admin:admin
    assert(endpoint.called && endpoint.seen.getName() == "admin" && endpoint.seen.getAuthorities().length == 4);
    assert(cast(FactorGrantedAuthority) endpoint.seen.getAuthorities()[3]!is null);
    assert(response.getStatus() == 200);
}

/// A servlet that throws what method security would.
private final class Denying : FilterChain
{
    void doFilter(ServletRequest, ServletResponse)
    {
        import flint.security.authorization : AuthorizationDeniedException;

        throw new AuthorizationDeniedException("Access Denied");
    }
}

unittest
{
    // An authenticated user denied by the application gets 403 from the access-denied handler.
    auto response = new MockHttpServletResponse;
    securedChain().doFilter(request("Basic YWRtaW46YWRtaW4="), response, new Denying);
    assert(response.getStatus() == 403 && response.getErrorMessage() == "Forbidden");
}

@("FilterChainProxy.fastEffect: petclinic's permit-all chain states the generic chain's headers and context")
unittest
{
    import flint.engine.aot.fast : FastFilterEffect;
    import flint.security.authentication : AnonymousAuthenticationToken;

    FastFilterEffect effect;
    assert(disabledChain().fastEffect(false, effect));
    // The same fields, in order, as the generic chain writes on a fresh response.
    auto response = new MockHttpServletResponse;
    disabledChain().doFilter(new MockHttpServletRequest("GET", "/api/owners/1"), response, new Endpoint);
    string[2][] generic;
    foreach (name; response.getHeaderNames())
        foreach (value; response.getHeaders(name))
            generic ~= [name, value];
    string[2][] stated;
    foreach (ref field; effect.fields)
        stated ~= [field.name, field.value];
    assert(stated == generic);
    assert(stated.length == 6 && stated[$ - 1] == ["X-Frame-Options", "SAMEORIGIN"]);
    // enter installs the anonymous token AnonymousAuthenticationFilter would; exit clears the context.
    effect.enter();
    assert(cast(AnonymousAuthenticationToken) SecurityContextHolder.getContext().getAuthentication() !is null);
    effect.exit();
    assert(SecurityContextHolder.getContext().getAuthentication() is null);
    // A security exception escaping the servlet is the translation filter's; others are not.
    assert(effect.handles(new imported!"flint.security.access".AccessDeniedException("denied")));
    assert(!effect.handles(new Exception("other")));
}

@("FilterChainProxy.fastEffect: a chain with authentication or a denying rule states no effect") unittest
{
    import flint.engine.aot.fast : FastFilterEffect;

    FastFilterEffect effect;
    assert(!securedChain().fastEffect(false, effect));
    auto rules = new RequestMatcherDelegatingAuthorizationManager;
    rules.add(AnyRequestMatcher.INSTANCE(), SingleResultAuthorizationManager!RequestAuthorizationContext.denyAll());
    Filter[] filters = [new AuthorizationFilter(rules)];
    assert(!new FilterChainProxy(new DefaultSecurityFilterChain(AnyRequestMatcher.INSTANCE(),
            filters)).fastEffect(false, effect));
}

@("AnonymousAuthenticationFilter defers the anonymous token to the context's first read, as Spring Security 6 does")
unittest
{
    import flint.security.authentication : AnonymousAuthenticationToken, UsernamePasswordAuthenticationToken;
    import flint.security.core.context : SecurityContextImpl;

    SecurityContextHolder.clearContext();
    auto filter = new AnonymousAuthenticationFilter("key");
    auto chain = new Endpoint;
    // The chain holds a deferred context: present, made on the first read with the token, the same one after.
    filter.doFilter(new MockHttpServletRequest("GET", "/"), new MockHttpServletResponse, chain);
    assert(SecurityContextHolder.hasContext());
    auto context = SecurityContextHolder.getContext();
    auto token = cast(AnonymousAuthenticationToken) context.getAuthentication();
    assert(token !is null && token.getPrincipal().get!string == "anonymousUser");
    assert(SecurityContextHolder.getContext() is context);
    SecurityContextHolder.clearContext();
    assert(!SecurityContextHolder.hasContext());
    // A context already holding an authentication keeps it; an empty one gets the token at once.
    auto user = new UsernamePasswordAuthenticationToken(Any.of("user"), Any.of("secret"));
    SecurityContextHolder.setContext(new SecurityContextImpl(user));
    filter.doFilter(new MockHttpServletRequest("GET", "/"), new MockHttpServletResponse, chain);
    assert(SecurityContextHolder.getContext().getAuthentication() is user);
    SecurityContextHolder.setContext(new SecurityContextImpl);
    filter.doFilter(new MockHttpServletRequest("GET", "/"), new MockHttpServletResponse, chain);
    assert(cast(AnonymousAuthenticationToken) SecurityContextHolder.getContext().getAuthentication() !is null);
    SecurityContextHolder.clearContext();
}
