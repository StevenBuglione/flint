// Ported from spring-data-commons 4.2.0: src/test/java/org/springframework/data/support/PageableExecutionUtilsUnitTests.java
// Copyright 2020-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module pageable_execution_utils_tests;

import flint.data.domain : PageRequest, Pageable;
import flint.data.support : PageableExecutionUtils;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : List;
import flint.java.util.function_.longsupplier : LongSupplier;
import std.exception : assertThrown;

@safe:

@("firstPageRequestIsLessThanOneFullPageDoesNotRequireTotal")
unittest
{
    int calls;
    auto page = PageableExecutionUtils.getPage(List!int.of(1, 2, 3), PageRequest.of(0, 10), () => ++calls);

    assert(page.getContent().toArray() == [1, 2, 3]);
    assert(page.getTotalElements() == 3 && calls == 0);
}

@("noPageableRequestDoesNotRequireTotal")
unittest
{
    int calls;
    auto page = PageableExecutionUtils.getPage(List!int.of(1, 2, 3), Pageable.unpaged(), () => ++calls);

    assert(page.getContent().toArray() == [1, 2, 3]);
    assert(page.getTotalElements() == 3 && calls == 0);
}

@("subsequentPageRequestIsLessThanOneFullPageDoesNotRequireTotal")
unittest
{
    int calls;
    auto page = PageableExecutionUtils.getPage(List!int.of(1, 2, 3), PageRequest.of(5, 10), () => ++calls);

    assert(page.getContent().toArray() == [1, 2, 3]);
    assert(page.getTotalElements() == 53 && calls == 0);
}

@("firstPageRequestHitsUpperBoundRequiresTotal")
unittest
{
    int calls;
    auto page = PageableExecutionUtils.getPage(List!int.of(1, 2, 3), PageRequest.of(0, 3), () => 3L + ++calls);

    assert(page.getContent().toArray() == [1, 2, 3]);
    assert(page.getTotalElements() == 4 && calls == 1);
}

@("subsequentPageRequestHitsUpperBoundRequiresTotal")
unittest
{
    int calls;
    auto page = PageableExecutionUtils.getPage(List!int.of(1, 2, 3), PageRequest.of(1, 3), () => 6L + ++calls);

    assert(page.getContent().toArray() == [1, 2, 3]);
    assert(page.getTotalElements() == 7 && calls == 1);
}

@("subsequentPageRequestWithoutResultRequiresRequireTotal")
unittest
{
    int calls;
    auto page = PageableExecutionUtils.getPage(List!int.of(), PageRequest.of(5, 10), () => 6L + ++calls);

    assert(page.getContent().isEmpty());
    assert(page.getTotalElements() == 7 && calls == 1);
}

@("Null inputs are rejected before a count can be requested")
unittest
{
    int calls;
    auto content = List!int.of(1, 2, 3);
    auto pageable = PageRequest.of(0, 3);
    long delegate() @safe total = () => ++calls;

    assertThrown!IllegalArgumentException(PageableExecutionUtils.getPage!int(null, pageable, total));
    assertThrown!IllegalArgumentException(PageableExecutionUtils.getPage(content, null, total));
    assertThrown!IllegalArgumentException(PageableExecutionUtils.getPage(content, pageable, total.init));
    assertThrown!IllegalArgumentException(PageableExecutionUtils.getPage(content, pageable, cast(LongSupplier) null));
    assert(calls == 0);
}

@("The LongSupplier overload still defers the count")
unittest
{
    int calls;
    auto total = LongSupplier.of(() => 6L + ++calls);
    auto content = List!int.of(1, 2, 3);
    auto partial = PageableExecutionUtils.getPage(content, PageRequest.of(0, 4), total);
    assert(partial.getTotalElements() == 3 && calls == 0);

    auto full = PageableExecutionUtils.getPage(content, PageRequest.of(0, 3), total);
    assert(full.getTotalElements() == 7 && calls == 1);
}
