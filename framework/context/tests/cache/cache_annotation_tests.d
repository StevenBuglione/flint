module flint.cache.cache_annotation_tests;

import flint.cache.annotation : Cacheable, CacheConfig, CacheEvict, CachePut, Caching;
import flint.engine.aot.descriptor : descriptorOf;
import flint.engine.aot.name : typeNameOf;

@safe:

@("single and multiple regions keep the operation metadata")
unittest
{
    const operation = Cacheable("books", key: "#title", unless: "#result == null", sync: true);
    assert(operation.value == ["books"]);
    assert(operation.key == "#title" && operation.unless == "#result == null");
    assert(operation.sync && operation.condition.length == 0);

    const eviction = CacheEvict(cacheNames: ["books", "authors"], allEntries: true);
    assert(eviction.cacheNames == ["books", "authors"]);
    assert(eviction.allEntries && !eviction.beforeInvocation);
}

@("caching groups the three operations and cache config supplies class defaults")
unittest
{
    auto operations = Caching([Cacheable("books")], [CachePut("authors", condition: "#valid")],
            [CacheEvict("books", beforeInvocation: true)]);
    assert(operations.cacheable[0].value == ["books"]);
    assert(operations.put[0].condition == "#valid");
    assert(operations.evict[0].beforeInvocation);

    const defaults = CacheConfig("catalog", cacheManager: "sharedCacheManager");
    assert(defaults.value == ["catalog"]);
    assert(defaults.cacheManager == "sharedCacheManager");
    assert(defaults.keyGenerator.length == 0 && defaults.cacheResolver.length == 0);
}

@CacheConfig("catalog")
private class Catalog
{
}

@("cache names merge through the constructor shorthand and its alias")
unittest
{
    auto configured = descriptorOf!Catalog.annotation(typeNameOf!CacheConfig);
    assert(configured !is null);
    const defaults = configured.value.get!CacheConfig();
    assert(defaults.value == ["catalog"] && defaults.cacheNames == defaults.value);
}
