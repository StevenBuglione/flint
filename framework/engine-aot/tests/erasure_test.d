/++
`assumeClass`'s debug check: catching the `AssertError` is not `@safe`, so this lives in a test module without
`@safe:`, as the other such tests do.
+/
module flint.engine.aot.erasure_test;

import flint.engine.aot.objects : assumeClass;

private class Animal
{
}

private class Plant
{
}

debug unittest
{
    import core.exception : AssertError;

    // Negative, debug builds: an element of another class is caught before it is used as a T.
    Object stray = new Plant;
    bool caught;
    try
        cast(void) assumeClass!Animal(stray);
    catch (AssertError)
        caught = true;
    assert(caught);
    assert(assumeClass!Animal(new Animal) !is null && assumeClass!Animal(null) is null);
}
