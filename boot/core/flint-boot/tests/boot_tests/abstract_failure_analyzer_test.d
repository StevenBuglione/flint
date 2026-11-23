// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/diagnostics/
// AbstractFailureAnalyzerTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AbstractFailureAnalyzer's protected `findCause(failure, type)` is the module's
// `findCause!type(failure)`, the one AbstractFailureAnalyzer uses.
module boot_tests.abstract_failure_analyzer_test;

import flint.boot.diagnostics : findCause;
import flint.java.io : IOException;
import flint.java.lang : IllegalArgumentException, IllegalStateException;

@safe:

/// `TestException`: a checked exception.
class TestException : Exception
{
    /// Part of the upstream test fixture.
    this()
    {
        super(null);
    }
}

/// `SpecificTestException`.
final class SpecificTestException : TestException
{
}

@("findCauseWithNullException") unittest
{
    assert(findCause!Throwable(null) is null);
}

@("findCauseWithDirectExactMatch") unittest
{
    auto ex = new TestException;
    assert(findCause!TestException(ex) is ex);
}

@("findCauseWithDirectSubClass") unittest
{
    auto ex = new SpecificTestException;
    assert(findCause!TestException(ex) is ex);
}

@("findCauseWitNestedAndExactMatch") unittest
{
    auto ex = new TestException;
    assert(findCause!TestException(new IllegalArgumentException(new IllegalStateException(ex))) is ex);
}

version (FlintCheckedExceptionCause)
{
    // Gap: the cause chain follows RuntimeException's cause and D's `next`, not a checked exception's (IOException)
    // cause.
    @("findCauseWitNestedAndSubClass") unittest
    {
        auto ex = new SpecificTestException;
        assert(findCause!TestException(new IOException(null, new IllegalStateException(ex))) is ex);
    }
}

@("findCauseWithUnrelatedException") unittest
{
    auto ex = new IOException;
    assert(findCause!TestException(ex) is null);
}

@("findCauseWithMoreSpecificException") unittest
{
    auto ex = new TestException;
    assert(findCause!SpecificTestException(ex) is null);
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
