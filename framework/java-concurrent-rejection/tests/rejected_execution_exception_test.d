module rejected_execution_exception_test;

import flint.java.lang : IllegalStateException, RuntimeException;
import flint.java.util.concurrent.rejectedexecutionexception : RejectedExecutionException;
import std.exception : assertThrown;

@safe:

private final class NamedCause : RuntimeException
{
    override string toString() const
    {
        return "named failure";
    }
}

private final class CustomRejection : RejectedExecutionException
{
    bool called;

    this(Throwable cause)
    {
        super("rejected", cause);
    }

    override RuntimeException initCause(Throwable cause)
    {
        called = true;
        return this;
    }
}

@("rejected execution is unchecked and empty detail means absence")
unittest
{
    static assert(is(RejectedExecutionException : RuntimeException));
    auto empty = new RejectedExecutionException;
    assert(empty.getMessage() is null && empty.getCause() is null);
    assert(empty.toString() == typeid(empty).name);
    auto cause = new NamedCause;
    assert(empty.initCause(cause) is empty && empty.getCause() is cause);
    assertThrown!IllegalStateException(empty.initCause(null));

    string detail = "full";
    foreach (message; [cast(string) null, "", detail[0 .. 0]])
    {
        auto absent = new RejectedExecutionException(message);
        assert(absent.getMessage() is null && absent.toString() == typeid(absent).name);
    }
    auto full = new RejectedExecutionException(detail);
    assert(full.getMessage() == detail && full.toString() == typeid(full).name ~ ": " ~ detail);
}

@("explicit execution rejection causes remain assigned and retain identity")
unittest
{
    auto cause = new NamedCause;
    auto explicitCause = new RejectedExecutionException("rejected", cause);
    assert(explicitCause.getMessage() == "rejected" && explicitCause.getCause() is cause);
    assertThrown!IllegalStateException(explicitCause.initCause(null));
    auto explicitNull = new RejectedExecutionException("", cast(Throwable) null);
    assert(explicitNull.getMessage() is null && explicitNull.getCause() is null);
    assertThrown!IllegalStateException(explicitNull.initCause(cause));

    auto inferred = new RejectedExecutionException(cause);
    assert(inferred.getMessage() == "named failure" && inferred.getCause() is cause);
    auto absent = new RejectedExecutionException(cast(Throwable) null);
    assert(absent.getMessage() is null && absent.getCause() is null);
    assertThrown!IllegalStateException(absent.initCause(cause));

    auto subclass = new CustomRejection(null);
    assert(!subclass.called && subclass.getCause() is null);
}
