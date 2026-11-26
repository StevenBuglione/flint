module flint.java.lang.runnable;

@safe:

/// Java's `Runnable`: a task with no arguments and no result (R9: APIs also accept `void delegate()`).
interface Runnable
{
    /// Run the task.
    void run();
}
