module aspectj_exception_tests;

import flint.aspectj.lang : NoAspectBoundException, SoftException;
import flint.java.lang : RuntimeException, javaToString;
import std.typecons : Nullable;

@safe:

private final class DisplayCause : RuntimeException
{
    override string toString() const
    {
        return "custom cause";
    }
}

@("A missing aspect reports its name without a cause") unittest
{
    auto unnamed = new NoAspectBoundException;
    assert(unnamed.getMessage() is null && unnamed.getCause() is null);

    auto named = new NoAspectBoundException(Nullable!string("Audit"), null);
    assert(named.getMessage() == "Audit" && named.getCause() is null);
}

@("Aspect initialization failure reports the cause and distinguishes empty and missing names") unittest
{
    auto cause = new DisplayCause;
    auto named = new NoAspectBoundException(Nullable!string("Audit"), cause);
    assert(named.getMessage() == "Exception while initializing Audit: custom cause");
    assert(named.getCause() is cause && named.next is null);

    auto missing = new NoAspectBoundException(Nullable!string.init, cause);
    assert(missing.getMessage() == "Exception while initializing null: custom cause");

    auto empty = new NoAspectBoundException(Nullable!string(""), cause);
    assert(empty.getMessage() == "Exception while initializing : custom cause");

    auto nativeCause = new Exception("native failure");
    auto failure = new NoAspectBoundException(Nullable!string("Audit"), nativeCause);
    assert(failure.getMessage() == "Exception while initializing Audit: " ~ javaToString(nativeCause));
    assert(failure.getCause() is nativeCause);
}

@("SoftException exposes exactly the wrapped failure with no detail message") unittest
{
    Throwable cause = new Exception("checked failure");
    auto failure = new SoftException(cause);
    assert(failure.getWrappedThrowable() is cause && failure.getCause() is cause);
    assert(failure.getMessage() is null && failure.next is null);

    auto empty = new SoftException(null);
    assert(empty.getWrappedThrowable() is null && empty.getCause() is null);
    assert(empty.getMessage() is null);
}
