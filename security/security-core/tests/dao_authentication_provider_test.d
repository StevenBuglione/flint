// Ported from spring-security 7.2.0: core/src/test/java/org/springframework/security/authentication/dao/DaoAuthenticationProviderTests.java
/*
 * Copyright 2004, 2005, 2006 Acegi Technology Pty Limited
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Modified by the Flint authors.
 */
module flint.security.dao_authentication_provider_test;

import flint.cache.concurrent : ConcurrentMapCacheManager;
import flint.context.i18n : LocaleContextHolder;
import flint.context.support : StaticMessageSource;
import flint.engine.aot.any : Any;
import flint.engine.aot.name : typeNameOf;
import flint.java.lang : IllegalArgumentException;
import flint.security.authentication : AccountExpiredException, BadCredentialsException,
    CredentialsExpiredException, DisabledException,
    InternalAuthenticationServiceException, LockedException, ProviderManager, UsernamePasswordAuthenticationToken;
import flint.security.authentication.dao : AbstractUserDetailsAuthenticationProvider, DaoAuthenticationProvider;
import flint.security.authentication.password : CompromisedPasswordChecker,
    CompromisedPasswordDecision, CompromisedPasswordException;
import flint.security.core : AuthorityUtils, GrantedAuthority;
import flint.security.core.authority : FactorGrantedAuthority;
import flint.security.core.userdetails : User, UserDetails, UserDetailsService, UsernameNotFoundException;
import flint.security.core.userdetails : UserDetailsPasswordService;
import flint.security.core.userdetails.cache : FlintCacheBasedUserCache, NullUserCache;
import flint.security.crypto.password : NoOpPasswordEncoder, PasswordEncoder;
import flint.security.crypto.bcrypt : BCryptPasswordEncoder;
import flint.security.crypto.factory : PasswordEncoderFactories;
import std.exception : collectException;
import std.typecons : Nullable;

@safe:

private final class Users : UserDetailsService
{
    string password = "koala";
    bool enabled = true;
    bool accountNonExpired = true;
    bool credentialsNonExpired = true;
    bool accountNonLocked = true;
    bool returnNull;
    Exception failure;
    int loads;

    UserDetails loadUserByUsername(string username)
    {
        ++loads;
        if (failure !is null)
            throw failure;
        if (username != "rod")
            throw new UsernameNotFoundException("not found");
        if (returnNull)
            return null;
        return new User(username, password, enabled, accountNonExpired, credentialsNonExpired,
                accountNonLocked, AuthorityUtils.createAuthorityList("ROLE_ONE", "ROLE_TWO"));
    }
}

private final class TestProvider : DaoAuthenticationProvider
{
    this(UserDetailsService users)
    {
        super(users);
        setPasswordEncoder(NoOpPasswordEncoder.getInstance());
    }

    UserDetailsService users()
    {
        return getUserDetailsService();
    }

    PasswordEncoder encoder()
    {
        return getPasswordEncoder();
    }
}

private UsernamePasswordAuthenticationToken request(string username = "rod", string password = "koala")
{
    return UsernamePasswordAuthenticationToken.unauthenticated(Any.of(username), Any.of(password));
}

private FlintCacheBasedUserCache userCache()
{
    return new FlintCacheBasedUserCache(new ConcurrentMapCacheManager().getCache("users"));
}

@("testGoesBackToAuthenticationDaoToObtainLatestPasswordIfCachedPasswordSeemsIncorrect")
unittest
{
    auto users = new Users;
    auto cache = userCache();
    AbstractUserDetailsAuthenticationProvider provider = new TestProvider(users);
    provider.setUserCache(cache);
    assert(provider.authenticate(request()).isAuthenticated());
    assert(cache.getUserFromCache("rod").getPassword() == "koala");

    users.password = "easternLongNeckTurtle";
    assert(provider.authenticate(request("rod", users.password)).isAuthenticated());
    assert(users.loads == 2 && cache.getUserFromCache("rod").getPassword() == users.password);
}

@("testAuthenticates")
unittest
{
    auto provider = new TestProvider(new Users);
    provider.setUserCache(userCache());
    auto token = request();
    token.setDetails(Any.of("192.168.0.1"));
    auto result = provider.authenticate(token);
    assert(cast(UsernamePasswordAuthenticationToken) result !is null);
    assert(cast(User) result.getPrincipal().asObject() !is null);
    assert(result.getCredentials().get!string == "koala");
    assert(result.getAuthorities()[0].getAuthority() == "ROLE_ONE");
    assert(result.getAuthorities()[1].getAuthority() == "ROLE_TWO");
    assert(result.getDetails().get!string == "192.168.0.1");
}

@("testAuthenticatesASecondTime")
unittest
{
    auto users = new Users;
    auto provider = new TestProvider(users);
    provider.setUserCache(userCache());
    auto result = provider.authenticate(request());
    auto second = provider.authenticate(result);
    assert(cast(UsernamePasswordAuthenticationToken) second !is null);
    assert(second.getCredentials().get!string == result.getCredentials().get!string && users.loads == 1);
}

@("testAuthenticatesWithForcePrincipalAsString")
unittest
{
    auto provider = new TestProvider(new Users);
    provider.setUserCache(userCache());
    provider.setForcePrincipalAsString(true);
    auto result = provider.authenticate(request());
    assert(cast(UsernamePasswordAuthenticationToken) result !is null);
    assert(result.getPrincipal().get!string == "rod");
}

@("testGettersSetters")
unittest
{
    auto provider = new TestProvider(new Users);
    auto cache = userCache();
    assert(cast(NoOpPasswordEncoder) provider.encoder() !is null);
    assert(cast(NullUserCache) provider.getUserCache() !is null);
    provider.setUserCache(cache);
    assert(provider.getUserCache() is cache && !provider.isForcePrincipalAsString());
    provider.setForcePrincipalAsString(true);
    assert(provider.isForcePrincipalAsString());
}

@("testStartupFailsIfNoUserCacheSet")
unittest
{
    auto provider = new TestProvider(new Users);
    assert(cast(NullUserCache) provider.getUserCache() !is null);
    provider.setUserCache(null);
    const failure = collectException!IllegalArgumentException(provider.afterPropertiesSet());
    assert(failure !is null && failure.msg == "A user cache must be set");
}

@("testStartupSuccess")
unittest
{
    auto users = new Users;
    auto provider = new TestProvider(users);
    provider.setUserCache(userCache());
    assert(provider.users() is users);
    provider.afterPropertiesSet();
}

@("testSupports")
unittest
{
    auto provider = new TestProvider(new Users);
    assert(provider.supports(typeNameOf!UsernamePasswordAuthenticationToken));
    assert(!provider.supports("flint.security.authentication.TestingAuthenticationToken"));
}

@("testReceivedBadCredentialsWhenCredentialsNotProvided")
unittest
{
    auto provider = new TestProvider(new Users);
    assert(collectException!BadCredentialsException(provider.authenticate(request("rod", null))) !is null);
}

@("testAuthenticateFailsIfAccountExpired")
unittest
{
    auto users = new Users;
    users.accountNonExpired = false;
    assert(collectException!AccountExpiredException(new TestProvider(users).authenticate(request())) !is null);
}

@("testAuthenticateFailsIfAccountLocked")
unittest
{
    auto users = new Users;
    users.accountNonLocked = false;
    assert(collectException!LockedException(new TestProvider(users).authenticate(request())) !is null);
}

@("testAuthenticateFailsIfCredentialsExpired")
unittest
{
    auto users = new Users;
    users.credentialsNonExpired = false;
    auto provider = new TestProvider(users);
    provider.setUserCache(userCache());
    assert(collectException!CredentialsExpiredException(provider.authenticate(request())) !is null);
    assert(collectException!BadCredentialsException(provider.authenticate(request("rod", "wrong"))) !is null);
}

@("testAuthenticateFailsIfUserDisabled")
unittest
{
    auto users = new Users;
    users.enabled = false;
    assert(collectException!DisabledException(new TestProvider(users).authenticate(request())) !is null);
}

@("testAuthenticateFailsWhenAuthenticationDaoHasBackendFailure")
unittest
{
    auto users = new Users;
    users.failure = new Exception("backend unavailable");
    const failure = collectException!InternalAuthenticationServiceException(new TestProvider(users)
            .authenticate(request()));
    assert(failure !is null && failure.getCause() is users.failure);
}

@("testDetectsNullBeingReturnedFromAuthenticationDao")
unittest
{
    auto users = new Users;
    users.returnNull = true;
    const failure = collectException!InternalAuthenticationServiceException(new TestProvider(users)
            .authenticate(request()));
    assert(failure !is null
            && failure.msg == "UserDetailsService returned null, which is an interface contract violation");
}

@("testAuthenticateFailsWithInvalidUsernameAndHideUserNotFoundExceptionFalse")
unittest
{
    auto provider = new TestProvider(new Users);
    provider.setHideUserNotFoundExceptions(false);
    assert(!provider.isHideUserNotFoundExceptions());
    assert(collectException!UsernameNotFoundException(provider.authenticate(request("missing"))) !is null);
}

@("testAuthenticateFailsWithInvalidUsernameAndHideUserNotFoundExceptionsWithDefaultOfTrue")
unittest
{
    auto provider = new TestProvider(new Users);
    assert(provider.isHideUserNotFoundExceptions());
    const failure = collectException!BadCredentialsException(provider.authenticate(request("missing")));
    assert(failure !is null && cast(const(UsernameNotFoundException)) failure.getCause() !is null);
}

@("DAO provider refreshes cached account status before accepting credentials")
unittest
{
    auto users = new Users;
    auto cache = userCache();
    auto provider = new TestProvider(users);
    provider.setUserCache(cache);
    users.enabled = false;
    cache.putUserInCache(users.loadUserByUsername("rod"));
    users.enabled = true;
    assert(provider.authenticate(request()).isAuthenticated());
    assert(users.loads == 2 && cache.getUserFromCache("rod").isEnabled());
}

@("ProviderManager still erases credentials with a DAO cache")
unittest
{
    auto users = new Users;
    auto cache = userCache();
    auto provider = new TestProvider(users);
    provider.setUserCache(cache);
    auto manager = new ProviderManager(provider);
    auto result = manager.authenticate(request());
    assert(result.getCredentials().isNull && cache.getUserFromCache("rod").getPassword() is null);
    assert(manager.authenticate(request()).getCredentials().isNull && users.loads == 2);
}

private final class RecordingEncoder : PasswordEncoder
{
    int encodes;
    int matchesCount;
    int upgrades;
    string lastRaw;
    string lastEncoded;
    bool upgrade;

    string encode(string raw)
    {
        ++encodes;
        return "encoded:" ~ raw;
    }

    bool matches(string raw, string encoded)
    {
        ++matchesCount;
        lastRaw = raw;
        lastEncoded = encoded;
        return raw == encoded;
    }

    bool upgradeEncoding(string)
    {
        ++upgrades;
        return upgrade;
    }
}

private final class PasswordUpdates : UserDetailsPasswordService
{
    UserDetails user;
    string password;
    int updates;

    UserDetails updatePassword(UserDetails user, Nullable!string newPassword)
    {
        this.user = user;
        password = newPassword.isNull ? null : newPassword.get;
        ++updates;
        return user;
    }
}

private final class PasswordChecker : CompromisedPasswordChecker
{
    string lastPassword;
    bool compromised;

    CompromisedPasswordDecision check(string password)
    {
        lastPassword = password;
        return new CompromisedPasswordDecision(compromised);
    }
}

@("authenticateWhenSuccessAndPasswordManagerThenUpdates")
unittest
{
    auto users = new Users;
    auto encoder = new RecordingEncoder;
    encoder.upgrade = true;
    auto updates = new PasswordUpdates;
    auto provider = new TestProvider(users);
    provider.setPasswordEncoder(encoder);
    provider.setUserDetailsPasswordService(updates);
    auto result = provider.authenticate(request());
    assert(updates.updates == 1 && updates.password == "encoded:koala");
    assert(updates.user is cast(UserDetails) result.getPrincipal().asObject());
    assert(result.getCredentials().get!string == "koala");
}

@("authenticateWhenBadCredentialsAndPasswordManagerThenNoUpdate")
unittest
{
    auto updates = new PasswordUpdates;
    auto provider = new TestProvider(new Users);
    provider.setUserDetailsPasswordService(updates);
    assert(collectException!BadCredentialsException(provider.authenticate(request("rod", "wrong"))) !is null);
    assert(updates.updates == 0);
}

@("authenticateWhenNotUpgradeAndPasswordManagerThenNoUpdate")
unittest
{
    auto encoder = new RecordingEncoder;
    auto updates = new PasswordUpdates;
    auto provider = new TestProvider(new Users);
    provider.setPasswordEncoder(encoder);
    provider.setUserDetailsPasswordService(updates);
    assert(provider.authenticate(request()).isAuthenticated());
    assert(updates.updates == 0 && encoder.upgrades == 1);
}

@("authenticateWhenPasswordLeakedThenException")
unittest
{
    auto checker = new PasswordChecker;
    checker.compromised = true;
    auto updates = new PasswordUpdates;
    auto encoder = new RecordingEncoder;
    encoder.upgrade = true;
    auto provider = new TestProvider(new Users);
    provider.setPasswordEncoder(encoder);
    provider.setUserDetailsPasswordService(updates);
    provider.setCompromisedPasswordChecker(checker);
    const failure = collectException!CompromisedPasswordException(provider.authenticate(request()));
    assert(failure !is null && failure.msg == "The provided password is compromised, please change your password");
    assert(checker.lastPassword == "koala" && updates.updates == 0 && encoder.upgrades == 0);
}

@("authenticateWhenPasswordNotLeakedThenNoException")
unittest
{
    auto checker = new PasswordChecker;
    auto provider = new TestProvider(new Users);
    provider.setCompromisedPasswordChecker(checker);
    assert(provider.authenticate(request()).isAuthenticated());
    assert(checker.lastPassword == "koala");
}

@("testUserNotFoundEncodesPassword")
unittest
{
    auto provider = new TestProvider(new Users);
    auto encoder = new RecordingEncoder;
    provider.setPasswordEncoder(encoder);
    provider.setHideUserNotFoundExceptions(false);
    provider.afterPropertiesSet();
    foreach (i; 0 .. 2)
        assert(collectException!UsernameNotFoundException(provider.authenticate(request("missing"))) !is null);
    assert(encoder.encodes == 1 && encoder.matchesCount == 2);
    assert(encoder.lastRaw == "koala" && encoder.lastEncoded == "encoded:userNotFoundPassword");
}

@("testUserNotFoundNullCredentials")
unittest
{
    auto provider = new TestProvider(new Users);
    auto encoder = new RecordingEncoder;
    provider.setPasswordEncoder(encoder);
    provider.setHideUserNotFoundExceptions(false);
    assert(collectException!UsernameNotFoundException(provider.authenticate(request("missing", null))) !is null);
    assert(encoder.matchesCount == 0);
}

@("testUserNotFoundBCryptPasswordEncoder")
unittest
{
    auto provider = new TestProvider(new Users);
    provider.setPasswordEncoder(new BCryptPasswordEncoder(4));
    provider.setHideUserNotFoundExceptions(false);
    assert(collectException!UsernameNotFoundException(provider.authenticate(request("missing"))) !is null);
}

@("testUserNotFoundDefaultEncoder")
unittest
{
    auto provider = new DaoAuthenticationProvider(new Users);
    provider.setHideUserNotFoundExceptions(false);
    assert(collectException!UsernameNotFoundException(provider.authenticate(request("missing", null))) !is null);
}

@("constructWhenPasswordEncoderProvidedThenSets")
unittest
{
    auto provider = new TestProvider(new Users);
    auto encoder = NoOpPasswordEncoder.getInstance();
    provider.setPasswordEncoder(encoder);
    assert(provider.encoder() is encoder);
}

@("testAuthenticateFailsWithInvalidUsernameAndChangePasswordEncoder")
unittest
{
    auto provider = new TestProvider(new Users);
    provider.setUserCache(userCache());
    assert(collectException!BadCredentialsException(provider.authenticate(request("missing"))) !is null);
    provider.setPasswordEncoder(PasswordEncoderFactories.createDelegatingPasswordEncoder());
    assert(collectException!BadCredentialsException(provider.authenticate(request("missing"))) !is null);
}

@("DAO provider retains a failed account check and optionally verifies credentials")
unittest
{
    auto users = new Users;
    users.enabled = false;
    auto provider = new TestProvider(users);
    auto encoder = new RecordingEncoder;
    provider.setPasswordEncoder(encoder);
    assert(collectException!DisabledException(provider.authenticate(request("rod", "wrong"))) !is null);
    assert(encoder.matchesCount == 1);
    provider.setAlwaysPerformAdditionalChecksOnUser(false);
    assert(collectException!DisabledException(provider.authenticate(request())) !is null);
    assert(encoder.matchesCount == 1);
}

@("authenticateWhenSuccessThenIssuesFactor")
unittest
{
    auto users = new Users;
    users.password = "{noop}koala";
    auto provider = new DaoAuthenticationProvider(users);
    auto result = provider.authenticate(request());
    auto authorities = result.getAuthorities();
    assert(authorities.length == 3);
    assert(cast(FactorGrantedAuthority) authorities[2]!is null
            && authorities[2].getAuthority() == FactorGrantedAuthority.PASSWORD_AUTHORITY);
}

@("testAuthenticateFailsForIncorrectPasswordCase")
unittest
{
    auto provider = new TestProvider(new Users);
    provider.setUserCache(userCache());
    assert(collectException!BadCredentialsException(provider.authenticate(request("rod", "KOala"))) !is null);
}

@("testAuthenticateFailsWithEmptyUsername")
unittest
{
    auto provider = new TestProvider(new Users);
    provider.setUserCache(userCache());
    assert(collectException!BadCredentialsException(provider.authenticate(request(null))) !is null);
}

@("testAuthenticateFailsWithInvalidPassword")
unittest
{
    auto provider = new TestProvider(new Users);
    provider.setUserCache(userCache());
    auto invalid = request("rod", "INVALID_PASSWORD");
    assert(collectException!BadCredentialsException(provider.authenticate(invalid)) !is null);
}

@("testAuthenticateFailsWithMixedCaseUsernameIfDefaultChanged")
unittest
{
    auto provider = new TestProvider(new Users);
    provider.setUserCache(userCache());
    assert(collectException!BadCredentialsException(provider.authenticate(request("RoD"))) !is null);
}

@("DAO provider applies custom checks and grants distinct mapped authorities before the password factor")
unittest
{
    auto provider = new TestProvider(new Users);
    int preChecks, postChecks;
    provider.setPreAuthenticationChecks((UserDetails user) {
        assert(user.getUsername() == "rod");
        ++preChecks;
    });
    provider.setPostAuthenticationChecks((UserDetails user) {
        assert(preChecks == 1 && user.getUsername() == "rod");
        ++postChecks;
    });
    provider.setAuthoritiesMapper((GrantedAuthority[] authorities) => [
        authorities[1], authorities[1]
    ]);
    auto result = provider.authenticate(request());
    assert(preChecks == 1 && postChecks == 1);
    auto granted = result.getAuthorities();
    assert(granted.length == 2 && granted[0].getAuthority() == "ROLE_TWO");
    assert(cast(FactorGrantedAuthority) granted[1]!is null);
}

@("DAO provider reads configured failure messages")
unittest
{
    auto provider = new TestProvider(new Users);
    auto messages = new StaticMessageSource;
    messages.addMessage("AbstractUserDetailsAuthenticationProvider.badCredentials",
            LocaleContextHolder.getLocale(), "Credentials rejected");
    provider.setMessageSource(messages);

    const failure = collectException!BadCredentialsException(provider.authenticate(request("rod", "wrong")));
    assert(failure !is null && failure.msg == "Credentials rejected");
}

@("DAO provider accepts concrete password-hook delegates")
unittest
{
    auto provider = new TestProvider(new Users);
    auto encoder = new RecordingEncoder;
    encoder.upgrade = true;
    provider.setPasswordEncoder(encoder);
    int updates, compromisedChecks;
    provider.setCompromisedPasswordChecker((string password) {
        assert(password == "koala");
        ++compromisedChecks;
        return new CompromisedPasswordDecision(false);
    });
    provider.setUserDetailsPasswordService((UserDetails user, Nullable!string password) {
        assert(compromisedChecks == 1 && password.get == "encoded:koala");
        ++updates;
        return user;
    });
    assert(provider.authenticate(request()).isAuthenticated());
    assert(updates == 1);
}
