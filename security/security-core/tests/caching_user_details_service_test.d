module flint.security.caching_user_details_service_test;

import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.security.authentication : CachingUserDetailsService;
import flint.security.core.userdetails : User, UserCache, UserDetails, UserDetailsService, UsernameNotFoundException;
import flint.security.core.userdetails.cache : NullUserCache;
import std.exception : collectException;

@safe:

private final class RecordingUserDetailsService : UserDetailsService
{
    UserDetails result;
    UsernameNotFoundException failure;
    string requestedUsername;
    size_t loads;

    UserDetails loadUserByUsername(string username)
    {
        requestedUsername = username;
        ++loads;
        if (failure !is null)
            throw failure;
        return result;
    }

    override string toString()
    {
        return "test delegate";
    }
}

private final class RecordingUserCache : UserCache
{
    UserDetails user;
    string requestedUsername;
    size_t lookups;
    size_t writes;

    UserDetails getUserFromCache(string username)
    {
        requestedUsername = username;
        ++lookups;
        return user;
    }

    void putUserInCache(UserDetails user)
    {
        this.user = user;
        ++writes;
    }

    void removeUserFromCache(string username)
    {
        if (user !is null && user.getUsername() == username)
            user = null;
    }
}

@("CachingUserDetailsService loads again with its default cache")
unittest
{
    auto backing = new RecordingUserDetailsService;
    backing.result = new User("john", "password", null);
    auto service = new CachingUserDetailsService(backing);
    assert(cast(NullUserCache) service.getUserCache() !is null);
    assert(service.getUserCache() !is new CachingUserDetailsService(backing).getUserCache());

    assert(service.loadUserByUsername("john") is backing.result);
    assert(service.loadUserByUsername("john") is backing.result);
    assert(backing.loads == 2 && backing.requestedUsername == "john");
}

@("CachingUserDetailsService writes the original user on a miss and a hit")
unittest
{
    auto backing = new RecordingUserDetailsService;
    backing.result = new User("john", "password", null);
    auto service = new CachingUserDetailsService(backing);
    auto cache = new RecordingUserCache;
    service.setUserCache(cache);
    assert(service.getUserCache() is cache);

    assert(service.loadUserByUsername("john") is backing.result);
    assert(cache.requestedUsername == "john" && backing.requestedUsername == "john");
    assert(cache.user is backing.result && cache.writes == 1 && backing.loads == 1);

    assert(service.loadUserByUsername("john") is backing.result);
    assert(cache.user is backing.result && cache.lookups == 2 && cache.writes == 2 && backing.loads == 1);
}

@("CachingUserDetailsService rejects a null user and propagates a lookup failure")
unittest
{
    auto backing = new RecordingUserDetailsService;
    auto service = new CachingUserDetailsService(backing);
    auto cache = new RecordingUserCache;
    service.setUserCache(cache);

    const invalid = collectException!IllegalArgumentException(service.loadUserByUsername("john"));
    enum expected = "UserDetailsService test delegate returned null for username john. "
        ~ "This is an interface contract violation";
    assert(invalid !is null && invalid.msg == expected);
    assert(cache.writes == 0 && cache.user is null);

    auto missing = new UsernameNotFoundException("not found");
    backing.failure = missing;
    assert(collectException!UsernameNotFoundException(service.loadUserByUsername("john")) is missing);
    assert(cache.writes == 0 && cache.user is null && backing.loads == 2);
}

@("CachingUserDetailsService checks a missing delegate on a cache miss")
unittest
{
    auto service = new CachingUserDetailsService(null);
    auto cache = new RecordingUserCache;
    cache.user = new User("john", "password", null);
    service.setUserCache(cache);

    assert(service.loadUserByUsername("john") is cache.user);
    cache.removeUserFromCache("john");
    assert(collectException!NullPointerException(service.loadUserByUsername("john")) !is null);
    assert(cache.writes == 1);
    service.setUserCache(null);
    assert(collectException!NullPointerException(service.loadUserByUsername("john")) !is null);
}
