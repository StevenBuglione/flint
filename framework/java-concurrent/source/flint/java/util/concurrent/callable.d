/** Java SE 21 Callable, implemented from the API specification. */
module flint.java.util.concurrent.callable;

@safe:

/// A task that produces a result or raises an exception (R1, R3, R8, R9).
interface Callable(V)
{
    /// Runs the task and returns its result. Exceptions from the task propagate to the caller.
    V call();
}
