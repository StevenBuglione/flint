module flint.security.exception_cause_constructor_test;

import flint.java.lang : IllegalStateException, RuntimeException;
import flint.security.access : AccessDeniedException;
import flint.security.authentication : BadCredentialsException, DisabledException, ProviderNotFoundException;
import flint.security.authorization : AuthorizationDeniedException;
import flint.security.core : AuthenticationException;

@safe:

private final class TestAuthenticationException : AuthenticationException
{
    this(string message)
    {
        super(message);
    }
}

@("Security message-only constructors leave the cause unset")
unittest
{
    auto cause = new Exception("root");
    enum expectedLine = __LINE__ + 1;
    auto denial = new AccessDeniedException("denied");
    assert(denial.file == __FILE__ && denial.line == expectedLine);
    RuntimeException[] failures = [
        denial, new AuthorizationDeniedException("missing permission"),
        new TestAuthenticationException("failed"), new BadCredentialsException("invalid"),
        new DisabledException("disabled"), new ProviderNotFoundException("missing")
    ];
    foreach (failure; failures)
    {
        assert(failure.getCause() is null);
        assert(failure.initCause(cause) is failure);
        assert(failure.getCause() is cause);
    }
}

@("Security explicit null constructors follow the Java parent cause policy")
unittest
{
    auto cause = new Exception("root");
    auto parentForDenied = new RuntimeException("reference", cast(Throwable) null);
    auto parentForBadCredentials = new RuntimeException("reference", cast(Throwable) null);
    auto denied = new AccessDeniedException("denied", null, "caller.d", 23);
    auto badCredentials = new BadCredentialsException("invalid", cast(Throwable) null);
    assert(denied.file == "caller.d" && denied.line == 23);
    assert(causeCanBeInitialized(denied, cause) == causeCanBeInitialized(parentForDenied, cause));
    assert(causeCanBeInitialized(badCredentials, cause) == causeCanBeInitialized(parentForBadCredentials, cause));
}

private bool causeCanBeInitialized(RuntimeException failure, Throwable cause)
{
    try
    {
        failure.initCause(cause);
        assert(failure.getCause() is cause);
        return true;
    }
    catch (IllegalStateException)
    {
        assert(failure.getCause() is null);
        return false;
    }
}
