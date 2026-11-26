// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/domain/LimitUnitTests.java
// Copyright 2023-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.limit_tests;

import flint.data.domain : Limit, Pageable, PageRequest, Sort;
import flint.java.lang : IllegalStateException;
import flint.java.util : Objects;
import std.exception : assertThrown;

@safe:

@("unlimitedReusesInstance")
unittest
{
    assert(Limit.unlimited() is Limit.unlimited());
}

@("unlimitedReturnsTrueOnIsLimited")
unittest
{
    assert(Limit.unlimited().isUnlimited());
}

@("limitOfCapturesMaxValue")
unittest
{
    foreach (value; [int.min, -100, 0, 100, int.max])
        assert(Limit.of(value).max() == value);
}

@("isUnlimitedReturnsFalseIfLimited")
unittest
{
    foreach (value; [int.min, -100, 0, 100, int.max])
        assert(!Limit.of(value).isUnlimited());
}

@("unlimitedErrorsOnMax")
unittest
{
    assertThrown!IllegalStateException(Limit.unlimited().max());
}

@("equalsProperly")
unittest
{
    auto unlimited = cast(Object) Limit.unlimited();
    auto limited = cast(Object) Limit.of(5);

    assert(!Objects.equals(limited, unlimited));
    assert(!Objects.equals(unlimited, limited));
    assert(Objects.equals(unlimited, unlimited));
}

@("Limit value equality and hash agree")
unittest
{
    auto first = cast(Limit.Limited) Limit.of(-5);
    auto second = cast(Limit.Limited) Limit.of(-5);
    assert(first !is second && first == second);
    assert(first.hashCode() == -5 && second.hashCode() == -5);
    assert(!first.equals(cast(Object) Limit.of(5)));
    assert(!first.equals(null));
}

@("Pageable converts to a limit using page size and unpaged state")
unittest
{
    Pageable request = PageRequest.of(3, 10, Sort.by("id"));
    assert(request.toLimit().isLimited());
    assert(request.toLimit().max() == 10);
    assert(Pageable.unpaged().isUnpaged());
    assert(Pageable.unpaged().toOptional().isEmpty());
    assert(Pageable.unpaged().toLimit() is Limit.unlimited());
    assert(Pageable.unpaged(Sort.by("id")).toLimit() is Limit.unlimited());
}
