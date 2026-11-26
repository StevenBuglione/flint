/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/http/CacheControlTests.java.
Copyright 2002-present the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: JUnit and AssertJ assertions become D unittests and asserts.
+/
module flint.http.cache_control_tests;

import flint.http : CacheControl, HttpHeaders, ResponseEntity;
import flint.java.lang : IllegalStateException, NullPointerException;
import flint.java.time : Duration;
import flint.java.util.concurrent : TimeUnit;

@safe:

@("emptyCacheControl")
unittest
{
    assert(CacheControl.empty().getHeaderValue() is null);
}

@("maxAge")
unittest
{
    assert(CacheControl.maxAge(1, TimeUnit.HOURS).getHeaderValue() == "max-age=3600");
}

@("maxAge_duration")
unittest
{
    assert(CacheControl.maxAge(Duration.ofHours(1)).getHeaderValue() == "max-age=3600");
}

@("maxAgeAndDirectives")
unittest
{
    auto control = CacheControl.maxAge(3600, TimeUnit.SECONDS).cachePublic().noTransform();
    assert(control.getHeaderValue() == "max-age=3600, no-transform, public");
}

@("maxAgeAndSMaxAge")
unittest
{
    auto control = CacheControl.maxAge(1, TimeUnit.HOURS).sMaxAge(30, TimeUnit.MINUTES);
    assert(control.getHeaderValue() == "max-age=3600, s-maxage=1800");
}

@("maxAgeAndSMaxAge_duration")
unittest
{
    auto control = CacheControl.maxAge(Duration.ofHours(1)).sMaxAge(Duration.ofMinutes(30));
    assert(control.getHeaderValue() == "max-age=3600, s-maxage=1800");
}

@("noCachePrivate")
unittest
{
    assert(CacheControl.noCache().cachePrivate().getHeaderValue() == "no-cache, private");
}

@("noStore")
unittest
{
    assert(CacheControl.noStore().getHeaderValue() == "no-store");
}

@("mustUnderstand")
unittest
{
    assert(CacheControl.noStore().mustUnderstand().getHeaderValue() == "no-store, must-understand");
}

private void expectIllegalState(scope void delegate() @safe action)
{
    try
        action();
    catch (IllegalStateException)
        return;
    assert(false, "Expected illegal cache directives to be rejected");
}

@("mustUnderstandWithoutNoStoreRejected")
unittest
{
    expectIllegalState({ CacheControl.maxAge(1, TimeUnit.HOURS).mustUnderstand(); });
}

@("cachePublicAndCachePrivateRejected")
unittest
{
    expectIllegalState({ CacheControl.empty().cachePrivate().cachePublic(); });
    expectIllegalState({ CacheControl.empty().cachePublic().cachePrivate(); });
}

@("cachePublicWithNoStoreRejected")
unittest
{
    expectIllegalState({ CacheControl.noStore().cachePublic(); });
}

@("staleIfError")
unittest
{
    auto control = CacheControl.maxAge(1, TimeUnit.HOURS).staleIfError(2, TimeUnit.HOURS);
    assert(control.getHeaderValue() == "max-age=3600, stale-if-error=7200");
}

@("staleIfError_duration")
unittest
{
    auto control = CacheControl.maxAge(Duration.ofHours(1)).staleIfError(Duration.ofHours(2));
    assert(control.getHeaderValue() == "max-age=3600, stale-if-error=7200");
}

@("staleWhileRevalidate")
unittest
{
    auto control = CacheControl.maxAge(1, TimeUnit.HOURS).staleWhileRevalidate(2, TimeUnit.HOURS);
    assert(control.getHeaderValue() == "max-age=3600, stale-while-revalidate=7200");
}

@("staleWhileRevalidate_duration")
unittest
{
    auto control = CacheControl.maxAge(Duration.ofHours(1)).staleWhileRevalidate(Duration.ofHours(2));
    assert(control.getHeaderValue() == "max-age=3600, stale-while-revalidate=7200");
}

@("immutable")
unittest
{
    assert(CacheControl.maxAge(Duration.ofHours(1)).immutable_().getHeaderValue() == "max-age=3600, immutable");
}

@("Flint: cache control writers set and clear response headers")
unittest
{
    auto headers = HttpHeaders.create();
    headers.setCacheControl(CacheControl.noStore());
    assert(headers.getCacheControl() == "no-store");
    headers.setCacheControl(CacheControl.empty());
    assert(!headers.containsHeader(HttpHeaders.CACHE_CONTROL));
    headers.setCacheControl("private");
    headers.setCacheControl(null);
    assert(!headers.containsHeader(HttpHeaders.CACHE_CONTROL));

    auto response = ResponseEntity.ok().cacheControl(CacheControl.noCache().mustRevalidate()).build();
    assert(response.getHeaders().getCacheControl() == "no-cache, must-revalidate");
    auto cleared = ResponseEntity.ok().cacheControl("private").cacheControl(null).build();
    assert(!cleared.getHeaders().containsHeader(HttpHeaders.CACHE_CONTROL));

    try
        headers.setCacheControl(cast(CacheControl) null);
    catch (NullPointerException)
        return;
    assert(false, "Expected a null CacheControl to be rejected");
}

@("Flint: cache control renders signed second bounds in declaration order")
unittest
{
    auto control = CacheControl.maxAge(Duration.ofSeconds(long.min)).sMaxAge(long.max,
            TimeUnit.DAYS).staleWhileRevalidate(Duration.ofSeconds(long.max))
        .staleIfError(Duration.ofSeconds(-1)).proxyRevalidate();
    assert(control.getHeaderValue() == "max-age=-9223372036854775808, proxy-revalidate, s-maxage=9223372036854775807, "
            ~ "stale-if-error=-1, stale-while-revalidate=9223372036854775807");
    assert(CacheControl.empty().toString() == "CacheControl []");
}
