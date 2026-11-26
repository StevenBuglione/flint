// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/mapping/TargetAwareIdentifierAccessorUnitTests.java
// Copyright 2017-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module identifier_accessor_tests;

import flint.data.mapping : IdentifierAccessor, TargetAwareIdentifierAccessor;
import flint.engine.aot.any : Any;
import flint.java.lang : IllegalStateException;

@safe:

private final class Target
{
    string description;

    override string toString() const
    {
        return description;
    }
}

private final class TargetAccessor : TargetAwareIdentifierAccessor
{
    Any identifier;
    int calls;

    this(Any target)
    {
        super(target);
    }

    override Any getIdentifier()
    {
        ++calls;
        return identifier;
    }
}

private final class DefaultAccessor : IdentifierAccessor
{
    mixin IdentifierAccessor.Defaults;

    Any identifier;
    int calls;

    override Any getIdentifier()
    {
        ++calls;
        return identifier;
    }
}

@("throwsExceptionContainingInformationAboutTargetIfIdentifierAbsent")
unittest
{
    auto target = new Target;
    auto accessor = new TargetAccessor(Any.of(target));
    target.description = "the target object";
    IdentifierAccessor identifiers = accessor;
    accessor.identifier = Any.of(cast(Object) null);
    try
    {
        identifiers.getRequiredIdentifier();
        assert(0, "Expected a missing identifier error");
    }
    catch (IllegalStateException error)
    {
        assert(error.msg == "Could not obtain identifier from the target object");
    }
    assert(accessor.calls == 1);
}

@("required identifiers keep a present scalar zero, an empty string, and reference identity")
unittest
{
    auto contextual = new TargetAccessor(Any.of(17L));
    IdentifierAccessor identifiers = contextual;
    contextual.identifier = Any.of(0L);
    assert(identifiers.getRequiredIdentifier().get!long == 0L);
    auto object = new Object;
    contextual.identifier = Any.of(object);
    assert(identifiers.getRequiredIdentifier().asObject() is object);
    assert(contextual.calls == 2);

    auto ordinary = new DefaultAccessor;
    identifiers = ordinary;
    ordinary.identifier = Any.of("");
    assert(identifiers.getRequiredIdentifier().get!string.length == 0);
    ordinary.identifier = Any.init;
    try
    {
        identifiers.getRequiredIdentifier();
        assert(0, "Expected a missing identifier error");
    }
    catch (IllegalStateException error)
    {
        assert(error.msg == "Could not obtain identifier");
    }
    assert(ordinary.calls == 2);
}

@("missing identifiers render erased null and numeric targets with Java formatting")
unittest
{
    foreach (value, description; [Any.of(cast(string) null), Any.of(1.0)])
    {
        auto accessor = new TargetAccessor(description);
        try
        {
            accessor.getRequiredIdentifier();
            assert(0, "Expected a missing identifier error");
        }
        catch (IllegalStateException error)
        {
            assert(error.msg == [
                "Could not obtain identifier from null", "Could not obtain identifier from 1.0"
            ][value]);
        }
    }
}
