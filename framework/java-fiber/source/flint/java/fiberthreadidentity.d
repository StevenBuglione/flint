// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Flint composition of the Java Thread identity with engine reactor fibers.
module flint.java.fiberthreadidentity;

import core.exception : onInvalidMemoryOperationError;
import core.thread.osthread : Thread;
import flint.engine.reactor : FiberLocal;
import flint.java.lang.internal.threadcontrol : installThreadIdentityProvider;

@safe:

private shared FiberLocal!Object identity;

/// Flint extension for application composition. Install before any `Thread.currentThread` on a fiber.
/// Reinstalling this provider preserves existing identities.
bool installFiberThreadIdentityProvider() nothrow @nogc
{
    // Claim the process-wide slot before worker fibers can race to use it.
    // Writing back the current value also preserves identities on repeated startup.
    return identity.set(identity.get()).code == 0 && installThreadIdentityProvider(&currentIdentity);
}

private Object currentIdentity(bool create, Object candidate) @safe nothrow @nogc
{
    if (Thread.getThis() is null)
        onInvalidMemoryOperationError();

    auto current = identity.get();
    if (current !is null || !create || candidate is null)
        return current;

    // The Thread caller reports an unavailable creating lookup.
    return identity.set(candidate).code == 0 ? candidate : null;
}
