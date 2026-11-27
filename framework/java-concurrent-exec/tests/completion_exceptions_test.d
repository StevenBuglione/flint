module completion_exceptions_test;

import flint.java.lang : IllegalArgumentException, IllegalStateException, RuntimeException;
import flint.java.util.concurrent.cancellationexception : CancellationException;
import flint.java.util.concurrent.completionexception : CompletionException;
import std.exception : assertThrown;

@safe:

private final class NamedCause : RuntimeException
{
    override string toString() const
    {
        return "named failure";
    }
}

private final class ProtectedCompletion : CompletionException
{
    this()
    {
        super();
    }

    this(string message)
    {
        super(message);
    }
}

@("cancellation is unchecked, keeps Java's name and normalizes empty detail")
unittest
{
    static assert(is(CancellationException : IllegalStateException));
    auto empty = new CancellationException;
    assert(empty.getMessage() is null && empty.getCause() is null);
    assert(empty.toString() == typeid(empty).name);
    auto cause = new NamedCause;
    assert(empty.initCause(cause) is empty && empty.getCause() is cause);
    assertThrown!IllegalStateException(empty.initCause(null));

    string detail = "cancelled";
    foreach (message; [cast(string) null, "", detail[0 .. 0]])
    {
        auto absent = new CancellationException(message);
        assert(absent.getMessage() is null && absent.toString() == typeid(absent).name);
    }
    auto full = new CancellationException(detail);
    assert(full.getMessage() == detail && full.toString() == typeid(full).name ~ ": " ~ detail);
}

@("completion constructs the cause lifecycle the public contract specifies")
unittest
{
    static assert(is(CompletionException : RuntimeException));
    auto open = new ProtectedCompletion;
    assert(open.getMessage() is null && open.getCause() is null);
    auto cause = new NamedCause;
    assert(open.initCause(cause) is open && open.getCause() is cause);
    assertThrown!IllegalStateException(open.initCause(null));

    string detail = "failed";
    foreach (message; [cast(string) null, "", detail[0 .. 0]])
    {
        auto absent = new CompletionException(message, null);
        assert(absent.getMessage() is null && absent.getCause() is null);
        assertThrown!IllegalStateException(absent.initCause(cause));
    }
    auto explicitCause = new CompletionException(detail, cause);
    assert(explicitCause.getMessage() == detail && explicitCause.getCause() is cause);
    assertThrown!IllegalStateException(explicitCause.initCause(null));

    auto inferred = new CompletionException(cause);
    assert(inferred.getMessage() == "named failure" && inferred.getCause() is cause);
    assertThrown!IllegalStateException(inferred.initCause(null));
    auto absentCause = new CompletionException(cast(Throwable) null);
    assert(absentCause.getMessage() is null && absentCause.getCause() is null);
    assertThrown!IllegalStateException(absentCause.initCause(cause));
    auto selfOpen = new ProtectedCompletion;
    assertThrown!IllegalArgumentException(selfOpen.initCause(selfOpen));
}

@("completion's protected constructors keep the cause open for initialization")
unittest
{
    auto empty = new ProtectedCompletion;
    assert(empty.getMessage() is null && empty.getCause() is null);
    auto cause = new NamedCause;
    assert(empty.initCause(cause) is empty && empty.getCause() is cause);

    auto named = new ProtectedCompletion("protected");
    assert(named.getMessage() == "protected" && named.getCause() is null);
    assert(named.initCause(cause) is named && named.getCause() is cause);
}
