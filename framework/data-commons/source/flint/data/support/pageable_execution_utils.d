// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/support/PageableExecutionUtils.java
// Copyright 2020-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.support.pageable_execution_utils;

import flint.data.domain : Page, PageImpl, Pageable;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : List;
import flint.java.util.function_.longsupplier : LongSupplier;

@safe:

/// Builds a page, inferring the total from the result size and offset where possible.
abstract class PageableExecutionUtils
{
    private this()
    {
    }

    /// Apply the requested page to its query results. Invoke the supplier only when needed.
    static Page!T getPage(T)(List!T content, Pageable pageable, LongSupplier totalSupplier)
    {
        return getPage(content, pageable, totalSupplier is null ? null : totalSupplier.asDelegate());
    }

    /// Delegate overload for the count operation (R9).
    static Page!T getPage(T)(List!T content, Pageable pageable, scope long delegate() @safe totalSupplier)
    {
        if (content is null)
            throw new IllegalArgumentException("Content must not be null");
        if (pageable is null)
            throw new IllegalArgumentException("Pageable must not be null");
        if (totalSupplier is null)
            throw new IllegalArgumentException("TotalSupplier must not be null");

        const total = totalElements(content.size(), pageable, totalSupplier);
        return new PageImpl!T(content, pageable, total);
    }
}

private long totalElements(int size, Pageable pageable, scope long delegate() @safe totalSupplier)
{
    if (pageable.isUnpaged())
        return size;

    if (size < pageable.getPageSize())
    {
        const offset = pageable.getOffset();
        if (size != 0 || offset == 0)
            return offset + size;
    }

    return totalSupplier();
}
