// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/auditing/AuditorUnitTests.java
// Copyright 2020-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.auditing.auditor_tests;

import flint.data.auditing.auditor : Auditor;
import flint.data.domain : AuditorAware;
import flint.java.util : Optional;

@safe:

private alias StringAuditor = Auditor!string;

@("auditorOfEmptyOptionalIsNone")
unittest
{
    auto auditor = StringAuditor.ofOptional(Optional!string.empty());
    assert(auditor.equals(StringAuditor.none()));
    assert(!auditor.isPresent());
    assert(auditor.getValue().isNull);
}

@("auditorOfOptionalIsValue")
unittest
{
    auto auditor = StringAuditor.ofOptional(Optional!string.of("batman"));
    auto expected = StringAuditor.of("batman");
    assert(auditor.equals(expected));
    assert(auditor.hashCode() == expected.hashCode());
    assert(auditor.getValue().get() == "batman");
}

@("auditorOfMustNotWrapOtherAuditor")
unittest
{
    auto source = StringAuditor.of("batman");
    assert(StringAuditor.of(source) is source);
    assert(StringAuditor.ofOptional(Optional!StringAuditor.of(source)) is source);
}

@("auditorOfNullIsNone")
unittest
{
    assert(StringAuditor.of(null).equals(StringAuditor.none()));
    assert(!StringAuditor.of(null).isPresent());
}

@("An auditor provider may return a zero identifier or no auditor")
unittest
{
    static final class Provider : AuditorAware!long
    {
        Optional!long current;

        override Optional!long getCurrentAuditor()
        {
            return current;
        }
    }

    auto provider = new Provider();
    assert(!Auditor!long.ofOptional(provider.getCurrentAuditor()).isPresent());
    provider.current = Optional!long.of(0);
    auto auditor = Auditor!long.ofOptional(provider.getCurrentAuditor());
    assert(auditor.isPresent() && auditor.getValue().get() == 0);
}

@("The missing auditor is shared and renders consistently")
unittest
{
    static StringAuditor none() @nogc nothrow
    {
        return StringAuditor.none();
    }

    assert(none() is none());
    assert(none().equals(Auditor!long.none()));
    assert(none().hashCode() == Auditor!long.none().hashCode());
    assert(none().toString() == "Auditor.none()");
    assert(StringAuditor.of("").isPresent());
}
