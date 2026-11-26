module app;

import core.stdc.stdio : printf;
import flint.arena : Status;
import flint.java.util.concurrent.executor : Executor;
import flint.java.util.concurrent.executorservice : ExecutorService, OffloadExecutorService;
import workload : Command, fixtureOptions;

@safe:

@system int main(string[] args)
{
    auto host = new OffloadExecutorService(2, fixtureOptions());
    ExecutorService service = host;
    Executor executor = service;
    auto first = new Command(1);
    auto second = new Command(2);
    executor.execute(first);
    executor.execute(second);

    bool valid;
    if (args.length == 1)
    {
        service.shutdown();
        valid = service.isShutdown() && host.run().code == Status.ok && service.isTerminated()
            && first.completed() && second.completed();
    }
    else
    {
        auto pending = service.shutdownNow();
        valid = pending.size() == 2 && pending.get(0) is first && pending.get(1) is second
            && service.isShutdown() && service.isTerminated() && !first.completed() && !second.completed();
    }

    printf("%d\n", cast(int) !valid);
    return cast(int) !valid;
}
