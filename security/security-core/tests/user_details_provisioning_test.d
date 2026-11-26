// Ported from spring-security 7.2.0: core/src/test/java/org/springframework/security/provisioning/InMemoryUserDetailsManagerTests.java
/*
 * Copyright 2004-present the original author or authors.
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
module flint.security.user_details_provisioning_test;

import flint.context.i18n : LocaleContextHolder;
import flint.context.support : StaticMessageSource;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, IllegalStateException, RuntimeException;
import flint.security.access : AccessDeniedException;
import flint.security.authentication : AccountExpiredException, AccountStatusUserDetailsChecker,
    BadCredentialsException,
    CredentialsExpiredException,
    DisabledException, LockedException, ProviderManager, UsernamePasswordAuthenticationToken;
import flint.security.authentication.dao : DaoAuthenticationProvider;
import flint.security.core : Authentication, AuthorityUtils, CredentialsContainer;
import flint.security.core.context : SecurityContext, SecurityContextHolderStrategy, SecurityContextImpl;
import flint.security.core.userdetails : User, UserDetails, UserDetailsPasswordService, UsernameNotFoundException;
import flint.security.crypto.bcrypt : BCryptPasswordEncoder;
import flint.security.crypto.password : NoOpPasswordEncoder;
import flint.security.crypto.factory : PasswordEncoderFactories;
import flint.security.provisioning : InMemoryUserDetailsManager;
import std.exception : collectException;
import std.algorithm.searching : canFind;
import std.typecons : Nullable;

@safe:

private User user(string name = "user", string secret = "old")
{
    return new User(name, secret, AuthorityUtils.createAuthorityList("ROLE_USER"));
}

private final class FixedContext : SecurityContextHolderStrategy
{
    private SecurityContext context;
    int reads;

    this(string username)
    {
        context = new SecurityContextImpl(UsernamePasswordAuthenticationToken.authenticated(Any.of(username),
                Any.of("old"), AuthorityUtils.createAuthorityList("ROLE_USER")));
    }

    void clearContext()
    {
        context = createEmptyContext();
    }

    SecurityContext getContext()
    {
        ++reads;
        return context;
    }

    void setContext(SecurityContext context)
    {
        this.context = context;
    }

    SecurityContext createEmptyContext()
    {
        return new SecurityContextImpl;
    }
}

@("changePassword")
unittest
{
    auto stored = user();
    auto manager = new InMemoryUserDetailsManager(stored);
    UserDetailsPasswordService service = manager;
    service.updatePassword(stored, Nullable!string("newPassword"));
    assert(manager.loadUserByUsername(stored.getUsername()).getPassword() == "newPassword");
}

@("changePasswordWhenUsernameIsNotInLowercase")
unittest
{
    auto manager = new InMemoryUserDetailsManager(user());
    manager.updatePassword(user("User"), Nullable!string("newPassword"));
    assert(manager.loadUserByUsername("User").getPassword() == "newPassword");
}

@("changePasswordWhenUserNotFoundThenAppropriateException")
unittest
{
    auto manager = new InMemoryUserDetailsManager;
    const failure = collectException!RuntimeException(manager.updatePassword(user(), Nullable!string("newPassword")));
    assert(failure !is null && failure.msg == "user 'user' does not exist");
}

@("changePasswordWhenCustomSecurityContextHolderStrategyThenUses")
unittest
{
    auto manager = new InMemoryUserDetailsManager(user());
    auto strategy = new FixedContext("user");
    manager.setSecurityContextHolderStrategy(strategy);
    manager.changePassword(Nullable!string("old"), Nullable!string("newPassword"));
    assert(strategy.reads == 1);
    assert(manager.loadUserByUsername("user").getPassword() == "newPassword");
}

@("changePasswordWhenCurrentUsernameIsNotInLowercaseThenChangesPassword")
unittest
{
    auto manager = new InMemoryUserDetailsManager(user("User"));
    manager.setSecurityContextHolderStrategy(new FixedContext("User"));
    manager.changePassword(Nullable!string("old"), Nullable!string("newPassword"));
    assert(manager.loadUserByUsername("user").getPassword() == "newPassword");
}

@("createUserWhenUserAlreadyExistsThenException")
unittest
{
    auto manager = new InMemoryUserDetailsManager(user());
    const failure = collectException!IllegalArgumentException(manager.createUser(user("User")));
    assert(failure !is null && failure.msg == "user should not exist");
}

@("updateUserWhenUserDoesNotExistThenException")
unittest
{
    auto manager = new InMemoryUserDetailsManager;
    const failure = collectException!IllegalArgumentException(manager.updateUser(user()));
    assert(failure !is null && failure.msg == "user should exist");
}

@("loadUserByUsernameWhenUserNullThenException")
unittest
{
    auto manager = new InMemoryUserDetailsManager;
    const failure = collectException!UsernameNotFoundException(manager.loadUserByUsername("missing"));
    assert(failure !is null && failure.msg.canFind("missing"));
}

@("In-memory user erasure leaves the stored password intact")
unittest
{
    auto given = user();
    auto manager = new InMemoryUserDetailsManager(given);
    given.eraseCredentials();
    auto loaded = manager.loadUserByUsername("user");
    auto credentials = cast(CredentialsContainer) loaded;
    assert(credentials !is null);
    credentials.eraseCredentials();
    assert(loaded.getPassword() is null);
    assert(manager.loadUserByUsername("user").getPassword() == "old");
}

@("In-memory DAO upgrades keep the new encoding after ProviderManager erases credentials")
unittest
{
    auto initialEncoder = new BCryptPasswordEncoder(4);
    auto manager = new InMemoryUserDetailsManager(user("user", initialEncoder.encode("password")));
    auto provider = new DaoAuthenticationProvider(manager);
    auto upgradedEncoder = new BCryptPasswordEncoder(5);
    provider.setPasswordEncoder(upgradedEncoder);
    provider.setUserDetailsPasswordService(manager);
    auto auth = new ProviderManager(provider);
    auto request = UsernamePasswordAuthenticationToken.unauthenticated(Any.of("user"), Any.of("password"));
    auto result = auth.authenticate(request);
    assert(result.getCredentials().isNull);
    const upgraded = manager.loadUserByUsername("user").getPassword();
    assert(!upgradedEncoder.upgradeEncoding(upgraded) && upgradedEncoder.matches("password", upgraded));
    assert(auth.authenticate(request).isAuthenticated());
}

@("In-memory password changes require authentication and preserve the password on failed reauthentication")
unittest
{
    auto manager = new InMemoryUserDetailsManager(user());
    auto strategy = new FixedContext("user");
    manager.setSecurityContextHolderStrategy(strategy);
    auto provider = new DaoAuthenticationProvider(manager);
    provider.setPasswordEncoder(NoOpPasswordEncoder.getInstance());
    manager.setAuthenticationManager(new ProviderManager(provider));
    assert(collectException!BadCredentialsException(manager.changePassword(Nullable!string("wrong"),
            Nullable!string("newPassword"))) !is null);
    assert(manager.loadUserByUsername("user").getPassword() == "old");
    manager.changePassword(Nullable!string("old"), Nullable!string("newPassword"));
    assert(manager.loadUserByUsername("user").getPassword() == "newPassword");

    strategy.clearContext();
    assert(collectException!AccessDeniedException(manager.changePassword(Nullable!string("newPassword"),
            Nullable!string("another"))) !is null);
}

@("In-memory password changes fail if the current user no longer exists")
unittest
{
    auto manager = new InMemoryUserDetailsManager;
    manager.setSecurityContextHolderStrategy(new FixedContext("user"));
    assert(collectException!IllegalStateException(manager.changePassword(Nullable!string("old"),
            Nullable!string("newPassword"))) !is null);
}

@("AccountStatusUserDetailsChecker reports the first account failure")
unittest
{
    auto checker = new AccountStatusUserDetailsChecker;
    auto roles = AuthorityUtils.createAuthorityList("ROLE_USER");
    checker.check(user());
    assert(collectException!LockedException(checker.check(new User("user", "old", false, false,
            false, false, roles))) !is null);
    assert(collectException!DisabledException(checker.check(new User("user", "old", false, false,
            false, true, roles))) !is null);
    assert(collectException!AccountExpiredException(checker.check(new User("user", "old", true,
            false, false, true, roles))) !is null);
    assert(collectException!CredentialsExpiredException(checker.check(new User("user", "old", true,
            true, false, true, roles))) !is null);
}

@("AccountStatusUserDetailsChecker resolves configured messages")
unittest
{
    auto checker = new AccountStatusUserDetailsChecker;
    auto messages = new StaticMessageSource;
    messages.addMessage("AccountStatusUserDetailsChecker.disabled", LocaleContextHolder.getLocale(), "Disabled login");
    checker.setMessageSource(messages);
    auto disabled = new User("user", "old", false, true, true, true, AuthorityUtils.createAuthorityList("ROLE_USER"));
    const failure = collectException!DisabledException(checker.check(disabled));
    assert(failure !is null && failure.msg == "Disabled login");
    assert(collectException!IllegalArgumentException(checker.setMessageSource(null)) !is null);
}

@("loadUserByUsernameWhenNotInstanceOfCredentialsContainerThenReturnInstanceOfCredentialsContainer")
unittest
{
    auto given = user();
    auto store = new InMemoryUserDetailsManager(given);
    auto details = store.updatePassword(given, Nullable!string("updated"));
    assert(cast(CredentialsContainer) details is null);
    auto manager = new InMemoryUserDetailsManager(details);
    auto loaded = manager.loadUserByUsername("user");
    assert(cast(CredentialsContainer) loaded !is null && loaded.getPassword() == "updated");
}

@("authenticateWhenInvalidMissingOrMalformedIdThenException")
unittest
{
    enum missingPrefixMessage = "Given that there is no default password encoder configured, each password must "
        ~ "have a password encoding prefix. Please either prefix this password with '{noop}' or set a default "
        ~ "password encoder in `DelegatingPasswordEncoder`.";
    foreach (password, message; [
        "password": missingPrefixMessage,
        "bycrpt}password": "The name of the password encoder is improperly formatted or incomplete. The format "
        ~ "should be '{ENCODER}password'.",
        "{bycrptpassword": "The name of the password encoder is improperly formatted or incomplete. The format "
        ~ "should be '{ENCODER}password'.",
        "{ren&stimpy}password": "There is no password encoder mapped for the id 'ren&stimpy'. Check your "
        ~ "configuration to ensure it matches one of the registered encoders."
    ])
    {
        auto provider = new DaoAuthenticationProvider(new InMemoryUserDetailsManager(user("user", password)));
        provider.setPasswordEncoder(PasswordEncoderFactories.createDelegatingPasswordEncoder());
        auto manager = new ProviderManager(provider);
        auto request = UsernamePasswordAuthenticationToken.unauthenticated(Any.of("user"), Any.of("password"));
        const failure = collectException!IllegalArgumentException(manager.authenticate(request));
        assert(failure !is null && failure.msg == message);
    }
}

@("In-memory password updates can clear the nullable stored password")
unittest
{
    auto given = user();
    auto manager = new InMemoryUserDetailsManager(given);
    manager.updatePassword(given, Nullable!string.init);
    assert(manager.loadUserByUsername("user").getPassword() is null);
    assert(given.getPassword() == "old");
}
