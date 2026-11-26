// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Java SE 21 Executor, implemented from the public contract.
module flint.java.util.concurrent.executor;

import flint.java.lang.runnable : Runnable;

@safe:

/// Accepts work for execution under an implementation's scheduling policy.
interface Executor
{
    /// Execute the task. A null command raises NullPointerException.
    void execute(Runnable command);

    /// Accept an owned D delegate as a task (R9).
    final void execute(void delegate() @safe command)
    {
        if (command is null)
            rejectNullCommand();
        execute(new DelegateTask(command));
    }

    /// Resolve an untyped null through the canonical Runnable overload.
    final void execute(typeof(null) command)
    {
        execute(cast(Runnable) command);
    }
}

private final class DelegateTask : Runnable
{
    private void delegate() @safe command;

    this(void delegate() @safe command) pure nothrow @nogc
    {
        this.command = command;
    }

    override void run()
    {
        command();
    }
}

pragma(inline, false) private noreturn rejectNullCommand()
{
    import flint.java.lang : NullPointerException;

    throw new NullPointerException;
}
