// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Java SE 21 ScheduledFuture and RunnableScheduledFuture, implemented from the public contract.
module flint.java.util.concurrent.scheduledfuture;

import flint.java.util.concurrent.delayed : Delayed;
import flint.java.util.concurrent.future : Future, RunnableFuture;

@safe:

/// A `Future` whose result becomes available after the remaining `Delayed` time (R1, R3).
interface ScheduledFuture(V) : Delayed, Future!V
{
}

/// A `ScheduledFuture` that is also a `Runnable` the executor can run periodically (R1, R3).
interface RunnableScheduledFuture(V) : RunnableFuture!V, ScheduledFuture!V
{
    /// Whether the task runs repeatedly.
    bool isPeriodic();
}
