// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.concurrent.internal.managedoffload;

import flint.arena : ReactorError = Error, Status;
import flint.engine.reactor : OffloadInterrupt, OffloadWork, Reactor;
import flint.java.lang.runnable : Runnable;

@safe:

/// A D observation hook for an offloaded command that failed or was cancelled.
alias TaskFailureObserver = void delegate(Runnable, ReactorError, Exception) @safe nothrow @nogc;

package(flint.java.util.concurrent) struct ManagedOffloadResult
{
    ReactorError error;
    Exception failure;
}

package(flint.java.util.concurrent) Exception invokeManaged(Runnable command) nothrow
{
    try
        command.run();
    catch (Exception thrown)
        return thrown;
    return null;
}

// Reactor.offload keeps the caller's frame alive through final native
// completion. The registered worker may allocate and records its task
// exception separately from the reactor's cancellation or admission status.
// An Error is reported by the pool as a failed offload.
package(flint.java.util.concurrent) ManagedOffloadResult runManagedOffload(Runnable command,
        scope OffloadInterrupt interrupt = null) nothrow @nogc
{
    if (command is null)
        return ManagedOffloadResult(ReactorError(Status.invalidArgument, "managed offload requires a task"), null);

    Exception failure;
    scope OffloadWork work = () @safe nothrow{ failure = invokeManaged(command); };
    auto owner = Reactor.current();
    // For work that ran, the pool's atomic publication of completion and the
    // owner's observation in offload happen before the owner reads failure.
    auto status = owner.offload(work, interrupt);
    return ManagedOffloadResult(status, failure);
}
