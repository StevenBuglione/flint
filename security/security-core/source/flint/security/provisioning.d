// Ported from spring-security 7.2.0: core/src/main/java/org/springframework/security/provisioning
// Copyright 2004-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
/*
 * Ported from spring-security 7.2.0, core/src/main/java/org/springframework/security/provisioning/{
 * UserDetailsManager,InMemoryUserDetailsManager,MutableUser}.java.
 */

/// User stores that can be changed.
module flint.security.provisioning;

import core.atomic : atomicLoad, atomicStore;
import core.sync.mutex : Mutex;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException, IllegalStateException, RuntimeException;
import flint.security.access : AccessDeniedException;
import flint.security.authentication : AuthenticationManager, UsernamePasswordAuthenticationToken;
import flint.security.core : GrantedAuthority;
import flint.security.core.context : SecurityContextHolder, SecurityContextHolderStrategy;
import flint.security.core.userdetails : User, UserDetails, UserDetailsPasswordService,
    UserDetailsService, UsernameNotFoundException;
import std.typecons : Nullable;

@safe:

/// A UserDetailsService that can create and change users.
interface UserDetailsManager : UserDetailsService
{
    /// Add user.
    void createUser(UserDetails user);
    /// Replace user.
    void updateUser(UserDetails user);
    /// Remove the user named username.
    void deleteUser(string username);
    /// Whether the user named username exists.
    bool userExists(string username);
}

/// Users held in memory by lower-cased name.
class InMemoryUserDetailsManager : UserDetailsManager, UserDetailsPasswordService
{
    private StoredUser[string] users;
    private Mutex usersLock;
    private SecurityContextHolderStrategy strategy;
    private AuthenticationManager authenticationManager;

    /// A manager holding users.
    this(UserDetails[] users...)
    {
        usersLock = new Mutex;
        strategy = SecurityContextHolder.getContextHolderStrategy();
        foreach (user; users)
            store(user, false);
    }

    private void store(UserDetails user, bool replace)
    {
        const key = lower(user.getUsername());
        auto entry = new StoredUser(user);
        usersLock.lock_nothrow();
        scope (exit)
            usersLock.unlock_nothrow();
        bool exists = (key in users) !is null;
        if (exists != replace)
            throw new IllegalArgumentException(replace ? "user should exist" : "user should not exist");
        users[key] = entry;
    }

    /// Add a user whose name is new.
    void createUser(UserDetails user)
    {
        store(user, false);
    }

    /// Replace an existing user.
    void updateUser(UserDetails user)
    {
        store(user, true);
    }

    /// Remove the user named username.
    void deleteUser(string username)
    {

        usersLock.lock_nothrow();
        scope (exit)
            usersLock.unlock_nothrow();
        users.remove(lower(username));
    }

    /// Whether the user named username exists.
    bool userExists(string username)
    {
        return findUser(username) !is null;
    }

    /// Load a copy whose credentials can be erased independently of the stored password.
    UserDetails loadUserByUsername(string username)
    {
        auto user = findUser(username);
        if (user is null)
            throw UsernameNotFoundException.fromUsername(username);
        return new User(user.getUsername(), user.getPassword(), user.isEnabled(),
                user.isAccountNonExpired(), user.isCredentialsNonExpired(),
                user.isAccountNonLocked(), user.getAuthorities());
    }

    /// Change the current account's password, reauthenticating when a manager was supplied.
    void changePassword(Nullable!string oldPassword, Nullable!string newPassword)
    {
        auto authentication = strategy.getContext().getAuthentication();
        if (authentication is null)
            throw new AccessDeniedException(
                    "Can't change password as no Authentication object found in context for current user.");
        const username = authentication.getName();
        if (authenticationManager !is null)
        {
            auto credentials = oldPassword.isNull ? Any.init : Any.of(oldPassword.get);
            authenticationManager.authenticate(UsernamePasswordAuthenticationToken.unauthenticated(Any.of(username),
                    credentials));
        }
        if (replacePassword(username, newPassword) is null)
            throw new IllegalStateException("Current user doesn't exist in database.");
    }

    /// Persist a new encoded password for the named user's existing record.
    UserDetails updatePassword(UserDetails user, Nullable!string newPassword)
    {
        const username = user.getUsername();
        auto stored = replacePassword(username, newPassword);
        if (stored is null)
            throw new RuntimeException("user '" ~ username ~ "' does not exist");
        return stored;
    }

    /// Select the context strategy used by changePassword.
    void setSecurityContextHolderStrategy(SecurityContextHolderStrategy strategy)
    {
        if (strategy is null)
            throw new IllegalArgumentException("securityContextHolderStrategy cannot be null");
        this.strategy = strategy;
    }

    /// Select the manager that checks old credentials when changing the current password.
    void setAuthenticationManager(AuthenticationManager authenticationManager)
    {
        this.authenticationManager = authenticationManager;
    }

    private StoredUser findUser(string username)
    {
        const key = lower(username);
        usersLock.lock_nothrow();
        scope (exit)
            usersLock.unlock_nothrow();
        auto user = key in users;
        return user is null ? null : *user;
    }

    private StoredUser replacePassword(string username, Nullable!string newPassword)
    {
        const key = lower(username);
        auto value = new PasswordValue(newPassword.isNull ? null : newPassword.get);
        usersLock.lock_nothrow();
        scope (exit)
            usersLock.unlock_nothrow();
        auto user = key in users;
        if (user is null)
            return null;
        atomicStore((*user).password, value);
        return *user;
    }

    private static string lower(string text) pure nothrow
    {
        char[] result = text.dup;
        foreach (ref c; result)
            if (c >= 'A' && c <= 'Z')
                c += 32;
        return result.idup;
    }

    private static final class PasswordValue
    {
        const string value;

        this(string value)
        {
            this.value = value;
        }
    }

    private static final class StoredUser : UserDetails
    {
        private UserDetails user;
        private PasswordValue password;

        this(UserDetails user)
        {
            this.user = user;
            password = new PasswordValue(user.getPassword());
        }

        string getPassword()
        {
            return atomicLoad(password).value;
        }

        string getUsername()
        {
            return user.getUsername();
        }

        GrantedAuthority[] getAuthorities()
        {
            return user.getAuthorities();
        }

        bool isAccountNonExpired()
        {
            return user.isAccountNonExpired();
        }

        bool isAccountNonLocked()
        {
            return user.isAccountNonLocked();
        }

        bool isCredentialsNonExpired()
        {
            return user.isCredentialsNonExpired();
        }

        bool isEnabled()
        {
            return user.isEnabled();
        }
    }
}
