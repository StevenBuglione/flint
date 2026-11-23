/// Fixture for Flint AOT tests: `org.springframework.cache.annotation`.
module flint.cache.annotation;

import flint.core.annotation : AliasFor;

@safe:

/// `@Cacheable`.
struct Cacheable
{
    /// Alias of `cacheNames`.
    @AliasFor("cacheNames")
    string[] value;
    /// Cache names.
    @AliasFor("value")
    string[] cacheNames;
    /// SpEL key.
    string key;

    /// Java's single-value form: `@Cacheable("x")` (aot-contract.md section 2, R2.1).
    static Cacheable opCall(string value, string[] cacheNames = null, string key = null)
    {
        Cacheable result;
        result.value = [value];
        result.cacheNames = cacheNames;
        result.key = key;
        return result;
    }

    /// The array form, and the named-attribute form.
    static Cacheable opCall(string[] value = null, string[] cacheNames = null, string key = null)
    {
        Cacheable result;
        result.value = value;
        result.cacheNames = cacheNames;
        result.key = key;
        return result;
    }
}
