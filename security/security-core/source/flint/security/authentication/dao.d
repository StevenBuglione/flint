// Ported from spring-security 7.2.0: core/src/main/java/org/springframework/security/authentication/dao
// Copyright 2004-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
/*
 * Ported from spring-security 7.2.0, core/src/main/java/org/springframework/security/authentication/dao/{
 * AbstractUserDetailsAuthenticationProvider,DaoAuthenticationProvider}.java. The DaoAuthenticationProvider
 * keeps Flint's no-argument constructor, service setter and one-argument retrieval hook for existing callers.
 */

/// User-name and password authentication over a UserDetailsService.
module flint.security.authentication.dao;

import core.atomic : atomicLoad, atomicStore;
import std.typecons : Nullable;

import flint.beans.factory : InitializingBean;
import flint.context : MessageSource, MessageSourceAware;
import flint.context.support : DelegatingMessageSource, MessageSourceAccessor;
import flint.engine.aot.any : Any;
import flint.engine.aot.name : typeNameOf;
import flint.engine.aot.objects : objectEquals;
import flint.java.lang : IllegalArgumentException;
import flint.security.authentication : AccountExpiredException, AuthenticationProvider,
    BadCredentialsException, CredentialsExpiredException,
    DisabledException, InternalAuthenticationServiceException, LockedException, UsernamePasswordAuthenticationToken;
import flint.security.authentication.password : CompromisedPasswordChecker,
    CompromisedPasswordDecision, CompromisedPasswordException;
import flint.security.core : Authentication, AuthenticationException, GrantedAuthority;
import flint.security.core.authority : FactorGrantedAuthority;
import flint.security.core.authority.mapping : GrantedAuthoritiesMapper, NullAuthoritiesMapper;
import flint.security.core.userdetails : UserCache, UserDetails, UserDetailsChecker,
    UserDetailsPasswordService, UserDetailsService, UsernameNotFoundException;
import flint.security.core.userdetails.cache : NullUserCache;
import flint.security.crypto.factory : PasswordEncoderFactories;
import flint.security.crypto.password : PasswordEncoder;

@safe:

/// Shared user lookup, cache, account checks and token creation for user-details providers.
abstract class AbstractUserDetailsAuthenticationProvider : AuthenticationProvider, InitializingBean, MessageSourceAware
{
    protected MessageSourceAccessor messages;
    protected bool hideUserNotFoundExceptions = true;

    private UserCache userCache;
    private UserDetailsChecker preAuthenticationChecks;
    private UserDetailsChecker postAuthenticationChecks;
    private GrantedAuthoritiesMapper authoritiesMapper;
    private bool forcePrincipalAsString;
    private bool alwaysPerformAdditionalChecksOnUser = true;

    /// Defaults to a cache that stores no entries and Spring's account checks.
    this()
    {
        messages = new MessageSourceAccessor(new DelegatingMessageSource);
        userCache = new NullUserCache;
        preAuthenticationChecks = new DefaultPreAuthenticationChecks(this);
        postAuthenticationChecks = new DefaultPostAuthenticationChecks(this);
        authoritiesMapper = new NullAuthoritiesMapper;
    }

    /// Validate the configured strategies before running the provider's startup hook.
    final void afterPropertiesSet()
    {
        if (userCache is null)
            throw new IllegalArgumentException("A user cache must be set");
        if (messages is null)
            throw new IllegalArgumentException("A message source must be set");
        if (preAuthenticationChecks is null)
            throw new IllegalArgumentException("A pre authentication checks must be set");
        if (postAuthenticationChecks is null)
            throw new IllegalArgumentException("A post authentication checks must be set");
        doAfterPropertiesSet();
    }

    /// Validate the request, retrying a cached user's failed pre-checks once with current details.
    Authentication authenticate(Authentication authentication)
    {
        auto token = cast(UsernamePasswordAuthenticationToken) authentication;
        if (token is null)
            throw new IllegalArgumentException(
                    messages.getMessage("AbstractUserDetailsAuthenticationProvider.onlySupports",
                    null, "Only UsernamePasswordAuthenticationToken is supported"));

        const username = token.getPrincipal().isNull ? "NONE_PROVIDED" : token.getName();
        auto user = userCache.getUserFromCache(username);
        bool cacheWasUsed = user !is null;
        if (!cacheWasUsed)
        {
            try
                user = loadUser(username, token);
            catch (UsernameNotFoundException failure)
            {
                if (!hideUserNotFoundExceptions)
                    throw failure;
                throw new BadCredentialsException(badCredentialsMessage(), failure);
            }
        }

        try
            performPreCheck(user, token);
        catch (AuthenticationException failure)
        {
            if (!cacheWasUsed)
                throw failure;
            cacheWasUsed = false;
            user = loadUser(username, token);
            performPreCheck(user, token);
        }
        postAuthenticationChecks.check(user);
        if (!cacheWasUsed)
            userCache.putUserInCache(user);

        auto principal = forcePrincipalAsString ? Any.of(user.getUsername()) : Any.of(cast(Object) user);
        return createSuccessAuthentication(principal, token, user);
    }

    private UserDetails loadUser(string username, UsernamePasswordAuthenticationToken token)
    {
        auto user = retrieveUser(username, token);
        if (user is null)
            throw new IllegalArgumentException("retrieveUser returned null - a violation of the interface contract");
        return user;
    }

    private void performPreCheck(UserDetails user, UsernamePasswordAuthenticationToken token)
    {
        try
            preAuthenticationChecks.check(user);
        catch (AuthenticationException failure)
        {
            if (alwaysPerformAdditionalChecksOnUser)
            {
                try
                    additionalAuthenticationChecks(user, token);
                catch (AuthenticationException ignored)
                {
                    // Preserve the failed account check.
                }
            }
            throw failure;
        }
        additionalAuthenticationChecks(user, token);
    }

    /// Create an authenticated token with the mapped authorities and the original credentials and details.
    protected Authentication createSuccessAuthentication(Any principal, Authentication authentication, UserDetails user)
    {
        auto mapped = authoritiesMapper.mapAuthorities(user.getAuthorities());
        auto authorities = new GrantedAuthority[mapped.length + 1];
        size_t count;
        foreach (authority; mapped)
            addAuthority(authorities, count, authority);
        addAuthority(authorities, count,
                FactorGrantedAuthority.fromAuthority(FactorGrantedAuthority.PASSWORD_AUTHORITY));
        auto result = UsernamePasswordAuthenticationToken.authenticated(principal,
                authentication.getCredentials(), authorities[0 .. count]);
        result.setDetails(authentication.getDetails());
        return result;
    }

    private static void addAuthority(scope GrantedAuthority[] authorities, ref size_t count, GrantedAuthority authority)
    {
        foreach (existing; authorities[0 .. count])
            if (objectEquals(cast(Object) authority, cast(Object) existing))
                return;
        authorities[count++] = authority;
    }

    /// A provider-specific startup hook.
    protected void doAfterPropertiesSet()
    {
    }

    /// Retrieve the user or throw an authentication exception.
    protected abstract UserDetails retrieveUser(string username, UsernamePasswordAuthenticationToken authentication);

    /// Check the supplied credentials against the loaded or cached user.
    protected abstract void additionalAuthenticationChecks(UserDetails user, UsernamePasswordAuthenticationToken token);

    /// The cache used to find and store user details.
    UserCache getUserCache()
    {
        return userCache;
    }

    /// Replace the user cache.
    void setUserCache(UserCache userCache)
    {
        this.userCache = userCache;
    }

    /// Whether to return the user name as the principal.
    bool isForcePrincipalAsString()
    {
        return forcePrincipalAsString;
    }

    /// Set whether to return the user name as the principal.
    void setForcePrincipalAsString(bool forcePrincipalAsString)
    {
        this.forcePrincipalAsString = forcePrincipalAsString;
    }

    /// Whether to report unknown users as bad credentials.
    bool isHideUserNotFoundExceptions()
    {
        return hideUserNotFoundExceptions;
    }

    /// Report an unknown user as bad credentials by default.
    void setHideUserNotFoundExceptions(bool hide) pure nothrow @nogc
    {
        hideUserNotFoundExceptions = hide;
    }

    /// The source of failure messages.
    void setMessageSource(MessageSource messageSource)
    {
        messages = new MessageSourceAccessor(messageSource);
    }

    /// Whether this provider accepts the authentication type.
    bool supports(string authenticationType)
    {
        return authenticationType == typeNameOf!UsernamePasswordAuthenticationToken;
    }

    /// The checker used before credentials are checked.
    protected UserDetailsChecker getPreAuthenticationChecks()
    {
        return preAuthenticationChecks;
    }

    /// Replace the checker used before credentials are checked.
    void setPreAuthenticationChecks(UserDetailsChecker preAuthenticationChecks)
    {
        this.preAuthenticationChecks = preAuthenticationChecks;
    }

    /// Replace the checker with a delegate.
    void setPreAuthenticationChecks(void delegate(UserDetails) @safe check)
    {
        setPreAuthenticationChecks(check is null ? null : new DelegateChecker(check));
    }

    /// The checker used after credentials are checked.
    protected UserDetailsChecker getPostAuthenticationChecks()
    {
        return postAuthenticationChecks;
    }

    /// Replace the checker used after credentials are checked.
    void setPostAuthenticationChecks(UserDetailsChecker postAuthenticationChecks)
    {
        this.postAuthenticationChecks = postAuthenticationChecks;
    }

    /// Replace the checker with a delegate.
    void setPostAuthenticationChecks(void delegate(UserDetails) @safe check)
    {
        setPostAuthenticationChecks(check is null ? null : new DelegateChecker(check));
    }

    /// Set whether to check credentials even when the account pre-check fails.
    void setAlwaysPerformAdditionalChecksOnUser(bool alwaysPerformAdditionalChecksOnUser)
    {
        this.alwaysPerformAdditionalChecksOnUser = alwaysPerformAdditionalChecksOnUser;
    }

    /// Change how loaded authorities are granted to the authentication result.
    void setAuthoritiesMapper(GrantedAuthoritiesMapper authoritiesMapper)
    {
        this.authoritiesMapper = authoritiesMapper;
    }

    /// Map granted authorities through a delegate.
    void setAuthoritiesMapper(GrantedAuthority[]delegate(GrantedAuthority[]) @safe map)
    {
        setAuthoritiesMapper(map is null ? null : new DelegateAuthoritiesMapper(map));
    }

    package final string badCredentialsMessage()
    {
        return messages.getMessage("AbstractUserDetailsAuthenticationProvider.badCredentials", null, "Bad credentials");
    }

    private static final class DefaultPreAuthenticationChecks : UserDetailsChecker
    {
        private AbstractUserDetailsAuthenticationProvider provider;

        this(AbstractUserDetailsAuthenticationProvider provider)
        {
            this.provider = provider;
        }

        void check(UserDetails user)
        {
            auto messages = provider.messages;
            if (!user.isAccountNonLocked())
                throw new LockedException(messages.getMessage("AbstractUserDetailsAuthenticationProvider.locked",
                        null, "User account is locked"));
            if (!user.isEnabled())
                throw new DisabledException(messages.getMessage("AbstractUserDetailsAuthenticationProvider.disabled",
                        null, "User is disabled"));
            if (!user.isAccountNonExpired())
                throw new AccountExpiredException(messages.getMessage(
                        "AbstractUserDetailsAuthenticationProvider.expired", null, "User account has expired"));
        }
    }

    private static final class DefaultPostAuthenticationChecks : UserDetailsChecker
    {
        private AbstractUserDetailsAuthenticationProvider provider;

        this(AbstractUserDetailsAuthenticationProvider provider)
        {
            this.provider = provider;
        }

        void check(UserDetails user)
        {
            if (!user.isCredentialsNonExpired())
                throw new CredentialsExpiredException(provider.messages.getMessage(
                        "AbstractUserDetailsAuthenticationProvider.credentialsExpired",
                        null, "User credentials have expired"));
        }
    }
}

/// Loads a user from a UserDetailsService and checks the presented password.
class DaoAuthenticationProvider : AbstractUserDetailsAuthenticationProvider
{
    private UserDetailsService userDetailsService;
    private PasswordEncoder passwordEncoder;
    private TimingPassword timingPassword;
    private UserDetailsPasswordService userDetailsPasswordService;
    private CompromisedPasswordChecker compromisedPasswordChecker;

    // Published once per encoder by authentication calls. It contains only the synthetic encoded password.
    private static final class TimingPassword
    {
        private const PasswordEncoder encoder;
        private const string encoded;

        this(PasswordEncoder encoder, string encoded)
        {
            this.encoder = encoder;
            this.encoded = encoded;
        }
    }

    /// A provider with a delegating password encoder.
    this()
    {
        passwordEncoder = PasswordEncoderFactories.createDelegatingPasswordEncoder();
        userDetailsPasswordService = UserDetailsPasswordService.NOOP;
    }

    /// A provider over userDetailsService.
    this(UserDetailsService userDetailsService)
    {
        this();
        if (userDetailsService is null)
            throw new IllegalArgumentException("userDetailsService cannot be null");
        this.userDetailsService = userDetailsService;
    }

    /// Set the users when constructing the provider in stages.
    void setUserDetailsService(UserDetailsService userDetailsService) pure nothrow @nogc
    {
        this.userDetailsService = userDetailsService;
    }

    /// Set the password encoder. Throws IllegalArgumentException for null.
    void setPasswordEncoder(PasswordEncoder passwordEncoder)
    {
        if (passwordEncoder is null)
            throw new IllegalArgumentException("passwordEncoder cannot be null");
        atomicStore(this.passwordEncoder, passwordEncoder);
        atomicStore(timingPassword, cast(TimingPassword) null);
    }

    /// The configured password encoder.
    protected PasswordEncoder getPasswordEncoder()
    {
        return atomicLoad(passwordEncoder);
    }

    /// The configured user-details service.
    protected UserDetailsService getUserDetailsService()
    {
        return userDetailsService;
    }

    /// Require a user-details service at startup.
    protected override void doAfterPropertiesSet()
    {
        if (userDetailsService is null)
            throw new IllegalArgumentException("A UserDetailsService must be set");
    }

    /// Load the user for this authentication request.
    protected final override UserDetails retrieveUser(string username, UsernamePasswordAuthenticationToken token)
    {
        auto encoder = getPasswordEncoder();
        const encoded = timingPasswordFor(encoder);
        try
            return retrieveUser(username);
        catch (UsernameNotFoundException failure)
        {
            auto credentials = token.getCredentials();
            if (!credentials.isNull && credentials.typeName == "string")
            {
                if (encoded is null)
                    throw new IllegalArgumentException("userNotFoundEncodedPassword cannot be null");
                encoder.matches(credentials.get!string, encoded);
            }
            throw failure;
        }
    }

    private string timingPasswordFor(PasswordEncoder encoder)
    {
        auto cached = atomicLoad(timingPassword);
        if (cached !is null && cached.encoder is encoder)
            return cached.encoded;
        const encoded = encoder.encode("userNotFoundPassword");
        if (encoded !is null)
            atomicStore(timingPassword, new TimingPassword(encoder, encoded));
        return encoded;
    }

    /// The user named username. Wraps unexpected service failures.
    protected UserDetails retrieveUser(string username)
    {
        UserDetails loaded;
        try
            loaded = getUserDetailsService().loadUserByUsername(username);
        catch (UsernameNotFoundException e)
            throw e;
        catch (InternalAuthenticationServiceException e)
            throw e;
        catch (Exception e)
            throw new InternalAuthenticationServiceException(e.msg, e);
        if (loaded is null)
            throw new InternalAuthenticationServiceException(
                    "UserDetailsService returned null, which is an interface contract violation");
        return loaded;
    }

    /// Check the supplied password.
    protected override void additionalAuthenticationChecks(UserDetails user, UsernamePasswordAuthenticationToken token)
    {
        auto credentials = token.getCredentials();
        if (credentials.isNull || credentials.typeName != "string" || !getPasswordEncoder()
                .matches(credentials.get!string, user.getPassword()))
            throw new BadCredentialsException(badCredentialsMessage());
    }

    /// Install the repository service used to persist encoding upgrades.
    void setUserDetailsPasswordService(UserDetailsPasswordService service)
    {
        if (service is null)
            throw new IllegalArgumentException("userDetailsPasswordService cannot be null");
        userDetailsPasswordService = service;
    }

    /// Persist password updates through a delegate.
    void setUserDetailsPasswordService(UserDetails delegate(UserDetails, Nullable!string) @safe update)
    {
        setUserDetailsPasswordService(update is null ? null : new DelegatePasswordService(update));
    }

    /// Install a compromised-password checker that runs before any encoding upgrade.
    void setCompromisedPasswordChecker(CompromisedPasswordChecker checker)
    {
        if (checker is null)
            throw new IllegalArgumentException("compromisedPasswordChecker cannot be null");
        compromisedPasswordChecker = checker;
    }

    /// Check for compromised passwords through a delegate.
    void setCompromisedPasswordChecker(CompromisedPasswordDecision delegate(string) @safe check)
    {
        setCompromisedPasswordChecker(check is null ? null : new DelegateCompromisedPasswordChecker(check));
    }

    /// Check the valid password for compromise, persist a needed upgrade and create the authenticated token.
    protected override Authentication createSuccessAuthentication(Any principal,
            Authentication authentication, UserDetails user)
    {
        auto credentials = authentication.getCredentials();
        if (credentials.isNull)
            throw new IllegalArgumentException("Authentication.getCredentials() cannot be null");
        const presented = credentials.get!string;
        if (compromisedPasswordChecker !is null && compromisedPasswordChecker.check(presented).isCompromised())
            throw new CompromisedPasswordException("The provided password is compromised, please change your password");

        const existing = user.getPassword();
        auto service = userDetailsPasswordService;
        if (existing !is null && service !is UserDetailsPasswordService.NOOP)
        {
            auto encoder = getPasswordEncoder();
            if (encoder.upgradeEncoding(existing))
            {
                const encoded = encoder.encode(presented);
                user = service.updatePassword(user, encoded is null ? Nullable!string.init : Nullable!string(encoded));
            }
        }
        return super.createSuccessAuthentication(principal, authentication, user);
    }
}

private final class DelegateChecker : UserDetailsChecker
{
    private void delegate(UserDetails) @safe checkUser;

    this(void delegate(UserDetails) @safe checkUser)
    {
        this.checkUser = checkUser;
    }

    void check(UserDetails user)
    {
        checkUser(user);
    }
}

private final class DelegateAuthoritiesMapper : GrantedAuthoritiesMapper
{
    private GrantedAuthority[]delegate(GrantedAuthority[]) @safe map;

    this(GrantedAuthority[]delegate(GrantedAuthority[]) @safe map)
    {
        this.map = map;
    }

    GrantedAuthority[] mapAuthorities(GrantedAuthority[] authorities)
    {
        return map(authorities);
    }
}

private final class DelegatePasswordService : UserDetailsPasswordService
{
    private UserDetails delegate(UserDetails, Nullable!string) @safe update;

    this(UserDetails delegate(UserDetails, Nullable!string) @safe update)
    {
        this.update = update;
    }

    UserDetails updatePassword(UserDetails user, Nullable!string password)
    {
        return update(user, password);
    }
}

private final class DelegateCompromisedPasswordChecker : CompromisedPasswordChecker
{
    private CompromisedPasswordDecision delegate(string) @safe checkPassword;

    this(CompromisedPasswordDecision delegate(string) @safe checkPassword)
    {
        this.checkPassword = checkPassword;
    }

    CompromisedPasswordDecision check(string password)
    {
        return checkPassword(password);
    }
}
