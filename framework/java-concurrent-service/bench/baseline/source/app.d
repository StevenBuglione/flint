module app;

import core.stdc.stdio : printf;
import flint.arena : Status;
import flint.engine.reactor : OffloadWork, Reactor;
import flint.java.lang.runnable : Runnable;
import workload : Command, fixtureOptions;

@safe:

private final class NativeService
{
    private Runnable[2] pending;
    private bool completed;

    this(Runnable first, Runnable second)
    {
        pending = [first, second];
    }

    void dispatch() nothrow @nogc
    {
        auto owner = Reactor.current();
        scope (exit)
            owner.stop();

        foreach (command; pending)
        {
            bool failed;
            scope OffloadWork work = () @safe nothrow{
                try
                    command.run();
                catch (Exception)
                    failed = true;
            };
            if (owner.offload(work).code != Status.ok || failed)
                return;
        }
        completed = true;
    }
}

@system int main(string[] args)
{
    auto created = Reactor.create(fixtureOptions());
    if (!created.ok)
        return 1;

    auto first = new Command(1);
    auto second = new Command(2);
    auto service = new NativeService(first, second);
    bool valid;
    if (args.length == 1)
    {
        if (created.value.postStartup(0, &service.dispatch).code != Status.ok)
            return 1;
        valid = created.value.run().code == Status.ok && service.completed && first.completed() && second.completed();
    }
    else
    {
        created.value.stop();
        valid = service.pending[0] is first && service.pending[1] is second && !first.completed()
            && !second.completed();
    }

    printf("%d\n", cast(int) !valid);
    return cast(int) !valid;
}
