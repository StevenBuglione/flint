module executorservice_provider;

import flint.arena : Status;
import flint.engine.reactor : OffloadWork, Reactor, ReactorOptions;
import flint.java.lang.runnable : Runnable;

@safe:

private final class Command : Runnable
{
    int[] result;

    override void run()
    {
        result = [7];
    }
}

private final class NativeDispatch
{
    private Runnable pending;
    bool completed;

    this(Runnable pending)
    {
        this.pending = pending;
    }

    void dispatch() nothrow @nogc
    {
        auto owner = Reactor.current();
        scope (exit)
            owner.stop();

        bool failed;
        scope OffloadWork work = () @safe nothrow{
            try
                pending.run();
            catch (Exception)
                failed = true;
        };
        completed = owner.offload(work).code == Status.ok && !failed;
    }
}

int main(string[] args)
{
    ReactorOptions options;
    options.cores = 1;
    options.offloadThreads = 1;
    auto created = Reactor.create(options);
    if (!created.ok)
        return 1;

    auto task = new Command;
    auto dispatch = new NativeDispatch(task);
    if (created.value.postStartup(0, &dispatch.dispatch).code != Status.ok)
        return 1;

    if (args.length > 1)
    {
        created.value.stop();
        return dispatch.pending is task && task.result is null ? 0 : 1;
    }

    return created.value.run().code == Status.ok && dispatch.completed && task.result.length == 1
        && task.result[0] == 7 ? 0 : 1;
}
